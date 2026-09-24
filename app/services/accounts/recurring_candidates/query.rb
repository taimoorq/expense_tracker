module Accounts
  module RecurringCandidates
    class Query
      SUMMARY_FIELDS = %i[merchant category estimated_amount first_on last_on months_seen count status confidence history_through ambiguous evidence_digest].freeze

      def initialize(account:, activities: nil)
        @account = account
        @activities = activities
      end

      def call
        detected = Detector.new(account: @account, activities: @activities).call.index_by { |candidate| candidate[:key] }
        decisions = @account.recurring_candidate_decisions.index_by(&:merchant_key)
        (detected.keys | decisions.keys).map do |key|
          decision = decisions[key]
          candidate = detected[key] || restored_summary(decision)
          candidate.merge(key: key, decision: decision, review_status: decision&.status || "unreviewed", evidence_available: detected.key?(key))
        end
      end

      def find!(key)
        call.find { |candidate| candidate[:key] == key } || raise(ActiveRecord::RecordNotFound)
      end

      def self.summary(candidate)
        candidate.slice(*SUMMARY_FIELDS).as_json
      end

      private

      def restored_summary(decision)
        summary = decision.evidence_summary.symbolize_keys
        %i[first_on last_on history_through].each { |key| summary[key] = Date.iso8601(summary[key]) if summary[key].present? }
        summary.merge(rows: [], estimated_amount: summary[:estimated_amount].to_d, status: summary[:status]&.to_sym, confidence: summary[:confidence]&.to_sym)
      end
    end
  end
end
