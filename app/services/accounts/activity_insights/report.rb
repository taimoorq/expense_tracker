module Accounts
  module ActivityInsights
    class Report
      LEDGER_LIMIT = 75
      ROLLUP_LIMIT = 12
      SUBSCRIPTION_LIMIT = 12

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
        @activities ||= Accounts::ActivityEvidence.call(account: account)
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
          candidates = Accounts::RecurringCandidates::Query.new(account: account, activities: activities).call
          unresolved = candidates.select { |candidate| candidate[:review_status] == "unreviewed" && candidate[:evidence_available] }
          {
            active: unresolved.select { |candidate| candidate[:status] == :active },
            past: unresolved.select { |candidate| candidate[:status] == :past }
          }
        end
      end

      def merchant_for(activity)
        MerchantNormalizer.call(activity.description)
      end

      def primary_value(values)
        values.compact_blank.tally.max_by { |_value, count| count }&.first
      end
    end
  end
end
