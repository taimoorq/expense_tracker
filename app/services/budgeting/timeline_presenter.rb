module Budgeting
  class TimelinePresenter
    include ActionView::RecordIdentifier

    TEMPLATE_SOURCES = %w[pay_schedule subscription monthly_bill payment_plan credit_card_estimate].freeze

    def initialize(budget_month:, expense_entries:, default_timeline_view:)
      @budget_month = budget_month
      @expense_entries = preload_entries(Array(expense_entries))
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

    def groups_for_view
      @groups_for_view ||= grouped_entries.each_with_index.map do |(group_name, entries), index|
        {
          name: group_name,
          id: group_name.parameterize,
          open: index.zero?,
          total: entries.sum(&:cashflow_amount),
          count: entries.count,
          show_reason_column: group_name == "Other",
          rows: entries.map { |entry| row_for(entry, show_reason_column: group_name == "Other") }
        }
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

    def preload_entries(entries)
      ActiveRecord::Associations::Preloader.new(records: entries, associations: [ :budget_month, :source_account, :source_template ]).call

      credit_card_templates = entries.filter_map { |entry| entry.source_template if entry.source_template.is_a?(CreditCard) }
      if credit_card_templates.any?
        ActiveRecord::Associations::Preloader.new(records: credit_card_templates, associations: [ :linked_account, :payment_account ]).call
      end

      entries
    end

    def row_for(entry, show_reason_column:)
      impact = entry.cashflow_amount
      variable_payment_entry = variable_payment_entry?(entry)
      {
        dom_id: dom_id(entry),
        date: entry.occurred_on || "—",
        date_iso8601: entry.occurred_on&.iso8601,
        payee: entry.payee.presence || "—",
        account_name: entry.account_name.presence || "—",
        reason: reason_for_entry(entry),
        status: entry.status,
        status_label: entry.status.humanize,
        impact: impact,
        generated_from_template: generated_from_template?(entry),
        variable_payment_entry: variable_payment_entry,
        planned_amount: entry.planned_amount || 0,
        actual_amount: entry.actual_amount,
        mark_as_paid_path: Rails.application.routes.url_helpers.budget_month_expense_entry_path(entry.budget_month, entry),
        edit_path: Rails.application.routes.url_helpers.edit_budget_month_expense_entry_path(entry.budget_month, entry, timeline_view: default_timeline_view),
        delete_path: Rails.application.routes.url_helpers.budget_month_expense_entry_path(entry.budget_month, entry),
        template_edit_path: Rails.application.routes.url_helpers.edit_template_budget_month_expense_entry_path(entry.budget_month, entry),
        mark_as_paid_params: {
          mark_as_paid: "1",
          timeline_view: default_timeline_view,
          expense_entry: {
            actual_amount: entry.actual_amount.presence || entry.planned_amount
          }
        },
        delete_params: { timeline_view: default_timeline_view },
        show_reason_column: show_reason_column
      }
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
