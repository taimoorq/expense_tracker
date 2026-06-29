module Budgeting
  class PlanAndEditPresenter
    RecurringAction = Struct.new(
      :key,
      :title,
      :description,
      :preview,
      :button_path,
      :button_icon,
      :button_icon_classes,
      :button_classes,
      :button_label,
      :complete_button_label,
      :status_label,
      :complete_message,
      :missing_heading,
      :empty_summary,
      :status_unit,
      :status_suffix,
      :more_label,
      keyword_init: true
    ) do
      def complete?
        preview.fetch(:complete)
      end

      def remaining?
        remaining_count.positive?
      end

      def alternate?
        alternate_count.positive?
      end

      def action_available?
        !complete? || complete_button_label.present?
      end

      def current_button_label
        return complete_button_label if complete? && complete_button_label.present?

        button_label
      end

      def preview_items(limit = 4)
        preview.fetch(:previews).first(limit)
      end

      def alternate_items(limit = 4)
        preview.fetch(:alternate_previews, []).first(limit)
      end

      def status_summary
        return empty_summary unless total_count.positive?

        "#{matched_count} of #{total_count} #{status_unit} #{status_suffix}"
      end

      def more_summary(limit = 4)
        hidden_count = remaining_count - limit
        return nil unless hidden_count.positive?

        "+ #{hidden_count} more #{more_label}#{hidden_count == 1 ? "" : "s"}"
      end

      def alternate_more_summary(limit = 4)
        hidden_count = alternate_count - limit
        return nil unless hidden_count.positive?

        "+ #{hidden_count} more already found"
      end

      private

      def total_count
        preview.fetch(:total)
      end

      def matched_count
        preview.fetch(:matched)
      end

      def remaining_count
        preview.fetch(:remaining)
      end

      def alternate_count
        preview.fetch(:alternate_count, 0)
      end
    end

    NEXT_STEP_LABELS = {
      1 => "add recurring",
      2 => "add one-off items",
      3 => "review cleanup"
    }.freeze

    NEXT_STEP_CLASSES = {
      1 => "bg-emerald-100 text-emerald-800",
      2 => "bg-sky-100 text-sky-800",
      3 => "bg-amber-100 text-amber-800"
    }.freeze

    NEXT_STEP_ANCHORS = {
      1 => "#plan-recurring",
      2 => "#plan-one-off",
      3 => "#plan-review"
    }.freeze

    def initialize(budget_month:, expense_entries:, today: Date.current)
      @budget_month = budget_month
      @expense_entries = Array(expense_entries)
      @today = today
    end

    attr_reader :budget_month, :expense_entries, :today

    def recurring_actions
      @recurring_actions ||= [
        recurring_action(
          key: :pay_schedules,
          title: "Add Paychecks",
          description: "Recommended first so income is visible before the rest of the month is planned.",
          preview: generation_preview_for_type(:pay_schedules),
          button_path: routes.generate_paychecks_budget_month_path(budget_month),
          button_icon: "cash",
          button_icon_classes: "ta-action-icon",
          button_classes: "fb-btn-primary ta-action-btn w-full justify-center",
          button_label: "Add Paychecks",
          status_label: "Added",
          complete_message: "Paycheck entries are already in this month.",
          empty_summary: "No templates saved yet",
          status_unit: "paycheck transactions",
          status_suffix: "already in this month",
          more_label: "paycheck transaction"
        ),
        recurring_action(
          key: :subscriptions,
          title: "Add Subscriptions",
          description: "Bring in recurring subscriptions and services after income is in place.",
          preview: generation_preview_for_type(:subscriptions),
          button_path: routes.generate_subscriptions_budget_month_path(budget_month),
          button_icon: "repeat",
          button_icon_classes: "ta-action-icon text-indigo-600",
          button_classes: "fb-btn-secondary ta-action-btn w-full justify-center",
          button_label: "Add Subscriptions",
          status_label: "Added",
          complete_message: "Subscription entries are already in this month.",
          empty_summary: "No templates saved yet",
          status_unit: "subscription transactions",
          status_suffix: "already in this month",
          more_label: "subscription transaction"
        ),
        recurring_action(
          key: :monthly_bills,
          title: "Add Monthly Bills",
          description: "Pull in regular household bills so fixed outflows are not missed.",
          preview: generation_preview_for_type(:monthly_bills),
          button_path: routes.generate_monthly_bills_budget_month_path(budget_month),
          button_icon: "calendar-plus",
          button_icon_classes: "ta-action-icon text-sky-600",
          button_classes: "fb-btn-secondary ta-action-btn w-full justify-center",
          button_label: "Add Monthly Bills",
          status_label: "Added",
          complete_message: "Monthly bill entries are already in this month.",
          empty_summary: "No templates saved yet",
          status_unit: "monthly bill transactions",
          status_suffix: "already in this month",
          more_label: "monthly bill transaction"
        ),
        recurring_action(
          key: :payment_plans,
          title: "Add Payment Plans",
          description: "Add installment or debt-plan items so payoff work stays visible in the month.",
          preview: generation_preview_for_type(:payment_plans),
          button_path: routes.generate_payment_plans_budget_month_path(budget_month),
          button_icon: "template",
          button_icon_classes: "ta-action-icon text-violet-600",
          button_classes: "fb-btn-secondary ta-action-btn w-full justify-center",
          button_label: "Add Payment Plans",
          status_label: "Added",
          complete_message: "Payment-plan entries are already in this month.",
          empty_summary: "No templates saved yet",
          status_unit: "payment-plan transactions",
          status_suffix: "already in this month",
          more_label: "payment-plan transaction"
        ),
        recurring_action(
          key: :credit_cards,
          title: "Estimate Card Payments",
          description: "Run this after income and bills are in place so every active card gets a minimum payment entry.",
          preview: credit_card_generation_preview,
          button_path: routes.estimate_credit_cards_budget_month_path(budget_month),
          button_icon: "chart-bar",
          button_icon_classes: "ta-action-icon text-indigo-600",
          button_classes: "fb-btn-secondary ta-action-btn w-full justify-center",
          button_label: "Estimate Card Payments",
          complete_button_label: "Re-estimate Card Payments",
          status_label: "Estimated",
          empty_summary: "No credit cards saved yet",
          status_unit: "card payments",
          status_suffix: "already estimated",
          more_label: "card payment estimate",
          missing_heading: "Missing cards to estimate"
        )
      ]
    end

    def generation_actions_hidden?
      budget_month.complete_for_generation?
    end

    def template_actions_completed
      recurring_actions.count(&:complete?)
    end

    def recurring_actions_total
      recurring_actions.size
    end

    def manual_entries_count
      expense_entries.count { |entry| manual_entry?(entry) }
    end

    def due_planned_count
      expense_entries.count { |entry| entry.planned? && entry.occurred_on.present? && entry.occurred_on <= today }
    end

    def missing_details_count
      expense_entries.count { |entry| entry.occurred_on.blank? || entry.category.blank? || entry.payee.blank? }
    end

    def paid_missing_actual_count
      expense_entries.count { |entry| entry.paid? && entry.actual_amount.blank? }
    end

    def auto_completed_count
      expense_entries.count { |entry| auto_completed_entry?(entry) }
    end

    def review_attention_count
      due_planned_count + missing_details_count + paid_missing_actual_count + auto_completed_count
    end

    def month_items_count
      expense_entries.count
    end

    def next_recommended_step
      return 1 if !generation_actions_hidden? && template_actions_completed.zero? && month_items_count.zero?
      return 2 if manual_entries_count.zero?

      3
    end

    def next_recommended_label
      NEXT_STEP_LABELS.fetch(next_recommended_step)
    end

    def next_recommended_classes
      NEXT_STEP_CLASSES.fetch(next_recommended_step)
    end

    def next_recommended_anchor
      NEXT_STEP_ANCHORS.fetch(next_recommended_step)
    end

    private

    def recurring_action(missing_heading: "Missing and ready to add", complete_button_label: nil, complete_message: nil, **attributes)
      RecurringAction.new(
        missing_heading: missing_heading,
        complete_button_label: complete_button_label,
        complete_message: complete_message,
        **attributes
      )
    end

    def generation_preview_for_type(template_type)
      coverage_summaries = templates_for_type(template_type).map do |template|
        Recurring::MonthTemplateCoverage
          .new(template: template, budget_month: budget_month, entries: expense_entries)
          .summary
      end

      previews = sort_previews(coverage_summaries.flat_map { |summary| summary.fetch(:previews) })
      alternate_previews = sort_previews(coverage_summaries.flat_map { |summary| summary.fetch(:alternate_previews, []) })
      total_occurrences = coverage_summaries.sum { |summary| summary.fetch(:total) }
      matched_occurrences = coverage_summaries.sum { |summary| summary.fetch(:matched) }

      {
        total: total_occurrences,
        matched: matched_occurrences,
        remaining: previews.size,
        complete: total_occurrences.positive? && previews.empty?,
        previews: previews,
        alternate_count: alternate_previews.size,
        alternate_previews: alternate_previews
      }
    end

    def credit_card_generation_preview
      cards = templates_for_type(:credit_cards)
      previews = cards.filter_map do |card|
        next if expense_entries.any? { |entry| card.matches_entry_for_month?(entry, month_on: budget_month.month_on) }

        {
          payee: card.name,
          occurred_on: budget_month.month_on.change(day: [ card.due_day.to_i, budget_month.month_on.end_of_month.day ].min),
          planned_amount: card.minimum_payment,
          account: card.account_name,
          category: "Credit Card",
          amount_prefix: "minimum"
        }
      end

      {
        total: cards.size,
        matched: [ cards.size - previews.size, 0 ].max,
        remaining: previews.size,
        complete: cards.any? && previews.empty?,
        previews: sort_previews(previews)
      }
    end

    def templates_for_type(template_type)
      case template_type
      when :pay_schedules
        budget_month.user.pay_schedules.active_during_month(budget_month.month_on).to_a
      when :subscriptions
        budget_month.user.subscriptions.active_only.to_a
      when :monthly_bills
        budget_month.user.monthly_bills.active_only.select { |bill| bill.scheduled_for_month?(budget_month.month_on) }
      when :payment_plans
        budget_month.user.payment_plans.active_only.to_a
      when :credit_cards
        budget_month.user.credit_cards.active_only.to_a
      else
        []
      end
    end

    def sort_previews(previews)
      previews.sort_by { |preview| [ preview[:occurred_on] || Date.new(9999, 12, 31), preview[:payee].to_s.downcase ] }
    end

    def manual_entry?(entry)
      return entry.manual_origin? if entry.respond_to?(:manual_origin?)

      entry.source_file.blank? || entry.source_file == "manual"
    end

    def auto_completed_entry?(entry)
      return entry.auto_completed? if entry.respond_to?(:auto_completed?)

      entry.respond_to?(:auto_completed_at) && entry.auto_completed_at.present?
    end

    def routes
      Rails.application.routes.url_helpers
    end
  end
end
