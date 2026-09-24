module Overview
  class NextStepPolicy
    def initialize(context:)
      @context = context
    end

    def call
      workflow = context[:workflow_status]
      if workflow&.bank_review_count.to_i.positive?
        return {
          badge: "Needs review", title: "Review new bank activity",
          description: "Review posted transactions before adding them to your recorded activity. Pending transactions can wait.",
          primary_label: "Review Activity", primary_path: Rails.application.routes.url_helpers.activity_path(view: "bank"),
          secondary_label: "Bank connections", secondary_path: Rails.application.routes.url_helpers.bank_connections_path
        }
      end

      if context.fetch(:accounts).empty?
        return {
          badge: "Start here",
          title: "Add your first account",
          description: "Connect with SimpleFIN or add an account manually. You can combine both approaches.",
          primary_label: "Set up Accounts",
          primary_path: Rails.application.routes.url_helpers.accounts_path,
          secondary_label: "Create Account",
          secondary_path: Rails.application.routes.url_helpers.new_account_path
        }
      end

      current_month = context.fetch(:current_month)

      if current_month.nil?
        return {
          badge: "Next step",
          title: "Create your first month",
          description: "Start with one planned item or reuse recurring transactions. You can add more as you go.",
          primary_label: "Create Month",
          primary_path: Rails.application.routes.url_helpers.new_budget_month_path,
          secondary_label: "Open Recurring",
          secondary_path: Rails.application.routes.url_helpers.planning_templates_path
        }
      end

      if context.fetch(:current_month_entries).empty?
        return {
          badge: "Next step",
          title: "Build #{current_month.label}",
          description: "Add a planned item or bring in saved recurring transactions. Recorded activity stays separate from your plan.",
          primary_label: "Open Budget",
          primary_path: Rails.application.routes.url_helpers.budget_month_tab_path(current_month, "timeline"),
          secondary_label: "Open Plan and Edit",
          secondary_path: Rails.application.routes.url_helpers.budget_month_tab_path(current_month, "entries")
        }
      end

      if context.fetch(:review_attention_count).positive?
        return {
          badge: "Needs review",
          title: "Review #{context.fetch(:review_attention_count)} attention item#{context.fetch(:review_attention_count) == 1 ? "" : "s"}",
          description: "Some entries are due, missing details, or marked paid without an actual amount.",
          primary_label: "Open Budget",
          primary_path: Rails.application.routes.url_helpers.budget_month_tab_path(current_month, "timeline"),
          secondary_label: "Open Plan and Edit",
          secondary_path: Rails.application.routes.url_helpers.budget_month_tab_path(current_month, "entries", review: "all", anchor: "plan-review")
        }
      end

      if context.fetch(:manual_entries_count).zero?
        return {
          badge: "Next step",
          title: "Add one-off items",
          description: "Recurring items are in place. Add exceptions, adjustments, or irregular spending next.",
          primary_label: "Add entry",
          primary_path: Rails.application.routes.url_helpers.new_wizard_budget_month_expense_entries_path(current_month),
          primary_turbo_frame: "entry_wizard_modal",
          secondary_label: "Open Budget",
          secondary_path: Rails.application.routes.url_helpers.budget_month_tab_path(current_month, "timeline")
        }
      end

      {
        badge: "On track",
        title: "Keep the month current",
        description: "Make manual adjustments as the month changes, mark items paid as they happen, and keep review views current.",
        primary_label: "Open Budget",
        primary_path: Rails.application.routes.url_helpers.budget_month_tab_path(current_month, "timeline"),
        secondary_label: "Open Calendar",
        secondary_path: Rails.application.routes.url_helpers.budget_month_tab_path(current_month, "calendar")
      }
    end

    private

    attr_reader :context
  end
end
