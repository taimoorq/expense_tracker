module Overview
  class ReviewSummary
    def initialize(entries:, today: Date.current)
      @entries = entries
      @today = today
    end

    def call
      due_planned_count = entries.count { |entry| entry.planned? && entry.occurred_on.present? && entry.occurred_on <= today }
      missing_details_count = entries.count { |entry| entry.occurred_on.blank? || entry.category.blank? || entry.payee.blank? }
      paid_missing_actual_count = entries.count { |entry| entry.paid? && entry.actual_amount.blank? }

      {
        due_planned_count: due_planned_count,
        missing_details_count: missing_details_count,
        paid_missing_actual_count: paid_missing_actual_count,
        review_attention_count: due_planned_count + missing_details_count + paid_missing_actual_count,
        manual_entries_count: entries.count { |entry| entry.source_file.blank? },
        linked_entries_count: entries.count { |entry| entry.source_account_id.present? },
        linked_paid_entries_count: entries.count { |entry| entry.source_account_id.present? && entry.paid? }
      }
    end

    private

    attr_reader :entries, :today
  end
end
