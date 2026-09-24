module Budgeting
  class FullListRow
    def initialize(entry)
      @entry = entry
    end

    def amount
      return 0.to_d if entry.skipped?

      entry.paid? ? entry.actual_amount : entry.planned_amount
    end

    def sign
      return "" if amount.nil? || amount.zero?

      entry.income? ? "+" : "−"
    end

    def income?
      entry.income? && amount&.positive?
    end

    def comparison
      if entry.skipped? || (entry.paid? && entry.planned_amount != entry.actual_amount)
        [ "Planned", entry.planned_amount ] if entry.planned_amount.present?
      elsif entry.planned? && entry.actual_amount&.positive? && entry.actual_amount != entry.planned_amount
        [ "Actual", entry.actual_amount ]
      end
    end

    def missing_amount_label
      entry.paid? ? "Actual not recorded" : "Amount not set"
    end

    def status_icon
      { "paid" => "check-circle", "planned" => "calendar-month", "skipped" => "x" }.fetch(entry.status)
    end

    private

    attr_reader :entry
  end
end
