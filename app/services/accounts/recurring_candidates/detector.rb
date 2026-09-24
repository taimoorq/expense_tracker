require "digest"

module Accounts
  module RecurringCandidates
    class Detector
      KEY_VERSION = 1
      VARIABLE_CATEGORY = /\b(?:restaurants?|dining|supermarkets?|grocer(?:y|ies)|gas|gasoline|food|travel|automotive)\b/i
      SUBSCRIPTION_HINT = /\b(?:subscription|member|membership|stream|cloud|hosting|storage|software|internet|wireless|phone|insurance|substack|youtube|netflix|spotify|github|anthropic|aws|geico|tesla|prisma|fly\.io)\b/i
      MONEY_MOVEMENT = /\b(?:payment|transfer|autopay|refund|cash advance|withdrawal)\b/i

      def self.key(description)
        # Version 1 is a durable identity contract, separate from display text.
        normalized = ActivityInsights::MerchantNormalizer.call(description).downcase.squish
        Digest::SHA256.hexdigest("v1:#{normalized}")
      end

      def self.eligible?(row)
        ActivityInsights::Classifier.call(row) == :charge && row.amount.positive? &&
          ![ row.description, row.activity_type, row.category ].join(" ").match?(MONEY_MOVEMENT)
      end

      def initialize(account:, activities: nil)
        @account = account
        @activities = activities
      end

      def call
        activities.select { |row| self.class.eligible?(row) }.group_by { |row| self.class.key(row.description) }
          .filter_map { |key, rows| candidate(key, rows) }
          .sort_by { |item| [ item[:status] == :active ? 0 : 1, item[:confidence] == :high ? 0 : 1, -item[:last_on].jd, item[:key] ] }
      end

      private

      attr_reader :account

      def activities
        @activities ||= Accounts::ActivityEvidence.call(account: account)
      end

      def candidate(key, rows)
        rows = rows.sort_by { |row| [ row.transaction_on, row.id ] }.reverse
        months = rows.map { |row| row.transaction_on.beginning_of_month }.uniq
        return if months.size < 2

        merchant = ActivityInsights::MerchantNormalizer.call(rows.first.description)
        category = rows.map(&:category).compact_blank.tally.max_by { |_value, count| count }&.first
        hinted = [ merchant, category, rows.first.activity_type ].join(" ").match?(SUBSCRIPTION_HINT)
        return if category.to_s.match?(VARIABLE_CATEGORY) && !hinted

        amounts = rows.map(&:amount).sort
        midpoint = amounts.size / 2
        estimate = amounts.size.odd? ? amounts[midpoint] : (amounts[midpoint - 1] + amounts[midpoint]) / 2
        stable = amounts.last - amounts.first <= estimate * BigDecimal("0.15")
        return unless stable || hinted

        latest = @latest_date ||= activities.select { |row| row.account_delta.negative? }.map(&:transaction_on).max
        last_on = rows.first.transaction_on
        status = if last_on >= latest - 45.days
          :active
        elsif months.size >= 3 && last_on < latest - 60.days
          :past
        end
        return unless status

        {
          key: key, merchant: merchant, category: category, estimated_amount: estimate,
          first_on: rows.last.transaction_on, last_on: last_on, months_seen: months.size,
          count: rows.size, status: status, confidence: months.size >= 3 && stable && hinted ? :high : :medium,
          history_through: (@history_through ||= activities.map(&:transaction_on).max),
          ambiguous: rows.size > months.size, rows: rows,
          evidence_digest: Digest::SHA256.hexdigest(rows.map { |row| [ row.fingerprint, row.transaction_on, row.amount.to_s, row.description ] }.to_json)
        }
      end
    end
  end
end
