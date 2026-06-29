module Overview
  class ReviewSummary
    def initialize(entries:, today: Date.current)
      @entries = entries
      @today = today
    end

    def call
      due_planned_count = entries.count { |entry| entry.planned? && entry.occurred_on.present? && entry.occurred_on <= today }
      due_soon_count = entries.count { |entry| entry.planned? && entry.occurred_on.present? && entry.occurred_on > today && entry.occurred_on <= today + 7.days }
      missing_details_count = entries.count { |entry| entry.occurred_on.blank? || entry.category.blank? || entry.payee.blank? }
      paid_missing_actual_count = entries.count { |entry| entry.paid? && entry.actual_amount.blank? }
      auto_completed_count = entries.count { |entry| auto_completed_entry?(entry) }

      {
        due_planned_count: due_planned_count,
        due_soon_count: due_soon_count,
        missing_details_count: missing_details_count,
        paid_missing_actual_count: paid_missing_actual_count,
        auto_completed_count: auto_completed_count,
        review_attention_count: due_planned_count + missing_details_count + paid_missing_actual_count + auto_completed_count,
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

    def auto_completed_entry?(entry)
      return entry.auto_completed? if entry.respond_to?(:auto_completed?)

      entry.respond_to?(:auto_completed_at) && entry.auto_completed_at.present?
    end
  end
end
