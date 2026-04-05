module Overview
  class NextStepPolicy
    def initialize(context:)
      @context = context
    end

    def call
      if context.fetch(:accounts).empty?
        return {
          badge: "Start here",
          title: "Add your first account",
          description: "Start with the real accounts you expect to use so templates and month entries have somewhere to link later.",
          primary_label: "Set up Accounts",
          primary_path: Rails.application.routes.url_helpers.accounts_path,
          secondary_label: "Create Account",
          secondary_path: Rails.application.routes.url_helpers.new_account_path
        }
      end

      if context.fetch(:template_total).zero?
        return {
          badge: "Recommended",
          title: "Set up recurring transactions",
          description: "Add the incoming and outgoing items you expect each month first, then your first month can pull that recurring structure in immediately.",
          primary_label: "Open Recurring",
          primary_path: Rails.application.routes.url_helpers.planning_templates_path,
          secondary_label: "Open Accounts",
          secondary_path: Rails.application.routes.url_helpers.accounts_path
        }
      end

      if context.fetch(:linked_template_total).zero?
        return {
          badge: "Recommended",
          title: "Link templates to accounts",
          description: "Link the templates you just set up so generated month entries and account views stay aligned from the start.",
          primary_label: "Manage Recurring",
          primary_path: Rails.application.routes.url_helpers.planning_templates_path,
          secondary_label: "Open Accounts",
          secondary_path: Rails.application.routes.url_helpers.accounts_path
        }
      end

      current_month = context.fetch(:current_month)

      if current_month.nil?
        return {
          badge: "Next step",
          title: "Create your first month",
          description: "Once accounts and recurring transactions are ready, create the month and import those recurring items into it.",
          primary_label: "Create Month",
          primary_path: Rails.application.routes.url_helpers.new_budget_month_path,
          secondary_label: "Open Recurring",
          secondary_path: Rails.application.routes.url_helpers.planning_templates_path
        }
      end

      if context.fetch(:current_month_entries).empty?
        return {
          badge: "Next step",
          title: "Import recurring transactions into #{current_month.label}",
          description: "Start the month by pulling in the recurring transactions you already saved, then adjust the entries from there.",
          primary_label: "Open Plan and Edit",
          primary_path: Rails.application.routes.url_helpers.budget_month_tab_path(current_month, "entries"),
          secondary_label: "Add Entry with Wizard",
          secondary_path: Rails.application.routes.url_helpers.new_wizard_budget_month_expense_entries_path(current_month),
          secondary_turbo_frame: "entry_wizard_modal"
        }
      end

      if context.fetch(:review_attention_count).positive?
        return {
          badge: "Needs review",
          title: "Review #{context.fetch(:review_attention_count)} attention item#{context.fetch(:review_attention_count) == 1 ? "" : "s"}",
          description: "Some entries are due, missing details, or marked paid without an actual amount.",
          primary_label: "Open Plan and Edit",
          primary_path: Rails.application.routes.url_helpers.budget_month_tab_path(current_month, "entries"),
          secondary_label: "Open Budget",
          secondary_path: Rails.application.routes.url_helpers.budget_month_tab_path(current_month, "timeline")
        }
      end

      if context.fetch(:manual_entries_count).zero?
        return {
          badge: "Next step",
          title: "Add one-off items",
          description: "Recurring items are in place. Add exceptions, adjustments, or irregular spending next.",
          primary_label: "Add Entry with Wizard",
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
