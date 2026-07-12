module Accounts
  module ActivityInsights
    class Report
      LEDGER_LIMIT = 75
      ROLLUP_LIMIT = 12
      SUBSCRIPTION_LIMIT = 12
      RECENT_ACTIVE_WINDOW = 45.days
      PAST_OVERDUE_WINDOW = 60.days
      VARIABLE_CATEGORY_PATTERN = /\b(?:restaurant|restaurants|dining|supermarket|supermarkets|grocery|groceries|gas|gasoline|food|travel|automotive)\b/i
      SUBSCRIPTION_HINT_PATTERN = /\b(?:subscription|member|membership|stream|cloud|hosting|storage|software|internet|wireless|phone|insurance|substack|youtube|netflix|spotify|github|anthropic|aws|geico|tesla|prisma|fly\.io)\b/i

      def initialize(account:)
        @account = account
      end

      def call
        {
          has_activity: activities.any?,
          total_rows: activities.size,
          latest_rows: latest_rows,
          import_history: import_history,
          started_on: activities.map(&:transaction_on).min,
          ended_on: activities.map(&:transaction_on).max,
          charges_total: charges.sum { |activity| activity.amount.to_d },
          credits_total: credits.sum { |activity| activity.amount.to_d },
          net_delta: activities.sum { |activity| activity.account_delta.to_d },
          merchant_rollups: merchant_rollups.first(ROLLUP_LIMIT),
          interest_fee_rollups: interest_fee_rollups,
          active_subscription_candidates: recurring_candidates.fetch(:active).first(SUBSCRIPTION_LIMIT),
          past_subscription_candidates: recurring_candidates.fetch(:past).first(SUBSCRIPTION_LIMIT)
        }
      end

      private

      attr_reader :account

      def activities
        @activities ||= account.account_activities.includes(:account_activity_import).recent_first.to_a
      end

      def latest_rows
        activities.first(LEDGER_LIMIT)
      end

      def import_history
        @import_history ||= account.account_activity_imports.order(created_at: :desc).limit(6).to_a
      end

      def charges
        @charges ||= activities.select { |activity| activity.account_delta.to_d.negative? }
      end

      def credits
        @credits ||= activities.select { |activity| activity.account_delta.to_d.positive? }
      end

      def merchant_rollups
        @merchant_rollups ||= grouped_charges.map do |merchant, rows|
          build_merchant_rollup(merchant, rows)
        end.sort_by { |rollup| [ -rollup.fetch(:total), rollup.fetch(:merchant) ] }
      end

      def grouped_charges
        @grouped_charges ||= charges.group_by { |activity| merchant_for(activity) }
      end

      def build_merchant_rollup(merchant, rows)
        sorted_rows = rows.sort_by(&:transaction_on)
        amounts = rows.map { |row| row.amount.to_d }

        {
          merchant: merchant,
          total: amounts.sum,
          count: rows.size,
          average: amounts.sum / rows.size,
          first_on: sorted_rows.first.transaction_on,
          last_on: sorted_rows.last.transaction_on,
          category: primary_value(rows.map(&:category)),
          activity_type: primary_value(rows.map(&:activity_type)),
          rows: sorted_rows.reverse
        }
      end

      def interest_fee_rollups
        @interest_fee_rollups ||= classified_rows
          .select { |classification, _activity| classification.in?([ :interest, :fee ]) }
          .group_by { |classification, activity| [ classification, activity.transaction_on.beginning_of_month ] }
          .map do |(classification, month_on), pairs|
            rows = pairs.map(&:last).sort_by(&:transaction_on)
            {
              type: classification,
              label: classification.to_s.humanize,
              month_on: month_on,
              total: rows.sum { |row| row.amount.to_d },
              count: rows.size,
              last_on: rows.last.transaction_on,
              rows: rows.reverse
            }
          end
          .sort_by { |rollup| [ -rollup.fetch(:month_on).jd, rollup.fetch(:label) ] }
      end

      def classified_rows
        @classified_rows ||= activities.map { |activity| [ Classifier.call(activity), activity ] }
      end

      def recurring_candidates
        @recurring_candidates ||= begin
          latest_date = charges.map(&:transaction_on).max
          candidates = merchant_rollups.filter_map do |rollup|
            build_recurring_candidate(rollup, latest_date)
          end

          {
            active: candidates.select { |candidate| candidate.fetch(:status) == :active }.sort_by { |candidate| [ -confidence_rank(candidate), -candidate.fetch(:last_on).jd ] },
            past: candidates.select { |candidate| candidate.fetch(:status) == :past }.sort_by { |candidate| [ candidate.fetch(:last_on), -confidence_rank(candidate) ] }
          }
        end
      end

      def build_recurring_candidate(rollup, latest_date)
        return if latest_date.blank?
        return if rollup.fetch(:count) < 2
        return if recurring_exclusion?(rollup)

        rows = rollup.fetch(:rows)
        months_seen = rows.map { |row| row.transaction_on.beginning_of_month }.uniq.sort
        return if months_seen.size < 2

        last_on = rows.map(&:transaction_on).max
        stable = stable_amounts?(rows)
        hinted = subscription_hint?(rollup)
        return if !stable && !hinted

        status = if last_on >= latest_date - RECENT_ACTIVE_WINDOW
          :active
        elsif months_seen.size >= 3 && last_on < latest_date - PAST_OVERDUE_WINDOW
          :past
        end
        return if status.blank?

        {
          merchant: rollup.fetch(:merchant),
          estimated_amount: median(rows.map { |row| row.amount.to_d }),
          last_on: last_on,
          months_seen: months_seen.size,
          count: rollup.fetch(:count),
          confidence: confidence(months_seen: months_seen, stable: stable, hinted: hinted),
          status: status,
          category: rollup.fetch(:category),
          rows: rows
        }
      end

      def recurring_exclusion?(rollup)
        category = rollup.fetch(:category).to_s
        category.match?(VARIABLE_CATEGORY_PATTERN) && !subscription_hint?(rollup)
      end

      def subscription_hint?(rollup)
        [ rollup.fetch(:merchant), rollup.fetch(:category), rollup.fetch(:activity_type) ].join(" ").match?(SUBSCRIPTION_HINT_PATTERN)
      end

      def stable_amounts?(rows)
        amounts = rows.map { |row| row.amount.to_d }.sort
        return false if amounts.empty?

        baseline = median(amounts)
        return true if baseline.zero?

        (amounts.last - amounts.first) <= (baseline * 0.15)
      end

      def confidence(months_seen:, stable:, hinted:)
        return :high if months_seen.size >= 3 && stable && hinted
        return :medium if stable || hinted

        :low
      end

      def confidence_rank(candidate)
        { high: 3, medium: 2, low: 1 }.fetch(candidate.fetch(:confidence), 0)
      end

      def merchant_for(activity)
        MerchantNormalizer.call(activity.description)
      end

      def primary_value(values)
        values.compact_blank.tally.max_by { |_value, count| count }&.first
      end

      def median(values)
        sorted = values.sort
        midpoint = sorted.length / 2

        return sorted[midpoint] if sorted.length.odd?

        (sorted[midpoint - 1] + sorted[midpoint]) / 2
      end
    end
  end
end
