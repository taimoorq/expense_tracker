module Budgeting
  class TimelinePresenter
    TEMPLATE_SOURCES = %w[pay_schedule subscription monthly_bill payment_plan credit_card_estimate].freeze

    def initialize(budget_month:, expense_entries:, default_timeline_view:)
      @budget_month = budget_month
      @expense_entries = Array(expense_entries)
      @default_timeline_view = default_timeline_view.presence_in(%w[sections full-list calendar]) || "sections"
    end

    attr_reader :budget_month, :expense_entries, :default_timeline_view

    def timeline_leftover
      budget_month&.calculated_leftover || expense_entries.sum(&:cashflow_amount)
    end

    def reason_pills
      @reason_pills ||= expense_entries.filter_map { |entry| reason_for_entry(entry).to_s.strip.presence }
        .tally
        .sort_by { |reason, count| [ -count, reason.downcase ] }
        .first(8)
    end

    def timeline_view_urls
      {
        sections: Rails.application.routes.url_helpers.budget_month_tab_path(budget_month, "timeline"),
        "full-list": Rails.application.routes.url_helpers.budget_month_tab_path(budget_month, "timeline", view: "full-list"),
        calendar: Rails.application.routes.url_helpers.budget_month_tab_path(budget_month, "calendar")
      }
    end

    def grouped_entries
      @grouped_entries ||= begin
        remaining_entries = ordered_entries.dup

        groups = group_rules.each_with_object([]) do |(group_name, matcher), memo|
          matches, remaining_entries = remaining_entries.partition { |entry| matcher.call(entry) }
          memo << [ group_name, matches ] if matches.any?
        end

        groups << [ "Other", remaining_entries ] if remaining_entries.any?
        groups
      end
    end

    def generated_from_template?(entry)
      TEMPLATE_SOURCES.include?(entry.source_file.to_s)
    end

    def variable_payment_entry?(entry)
      entry.source_file.in?(%w[payment_plan credit_card_estimate])
    end

    def reason_for_entry(entry)
      entry.category.presence || entry.section.humanize
    end

    private

    def ordered_entries
      @ordered_entries ||= expense_entries.sort_by { |entry| [ entry.occurred_on || Date.new(9999, 12, 31), entry.created_at ] }
    end

    def group_rules
      [
        [ "Income & Paychecks", ->(entry) { entry.income? || entry.source_file == "pay_schedule" || entry.category.to_s.downcase.include?("paycheck") } ],
        [ "Payment Plans", ->(entry) { entry.source_file == "payment_plan" || entry.category.to_s.downcase.include?("payment plan") } ],
        [ "Credit Card Payments", ->(entry) { entry.source_file == "credit_card_estimate" || entry.category.to_s.downcase.include?("credit card") } ],
        [ "Recurring Subscriptions", ->(entry) { entry.source_file == "subscription" || entry.category.to_s.downcase.include?("subscription") } ],
        [ "Monthly Fixed Bills", ->(entry) { entry.source_file == "monthly_bill" && entry.category.to_s.downcase.include?("monthly payment") } ],
        [ "Monthly Variable Bills", ->(entry) { entry.source_file == "monthly_bill" && entry.category.to_s.downcase.include?("variable") } ]
      ]
    end
  end
end
