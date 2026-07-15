module Overview
  class ReviewSummary
    def initialize(entries:, today: Date.current)
      @entries = entries
      @today = today
    end

    def call
      review = Budgeting::MonthReviewQuery.call(entries: entries, reason: "all", today: today)
      due_soon_count = entries.count { |entry| entry.planned? && entry.occurred_on.present? && entry.occurred_on > today && entry.occurred_on <= today + 7.days }

      {
        due_planned_count: review.count_for(:due),
        due_soon_count: due_soon_count,
        missing_details_count: review.count_for(:missing_details),
        paid_missing_actual_count: review.count_for(:missing_actual),
        auto_completed_count: review.count_for(:auto_completed),
        review_attention_count: review.issue_count,
        manual_entries_count: entries.count { |entry| manual_entry?(entry) },
        linked_entries_count: entries.count { |entry| entry.source_account_id.present? },
        linked_paid_entries_count: entries.count { |entry| entry.source_account_id.present? && entry.paid? }
      }
    end

    private

    attr_reader :entries, :today

    def manual_entry?(entry)
      return entry.manual_origin? if entry.respond_to?(:manual_origin?)

      entry.source_file.blank? || entry.source_file == "manual"
    end
  end
end
