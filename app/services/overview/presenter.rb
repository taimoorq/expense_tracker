module Overview
  class Presenter
    def initialize(user:, today: Date.current, data: nil)
      @today = today
      @data = data || Overview::PageData.new(user: user, today: today).call
    end

    def onboarding_status
      return status_payload(label: "Complete", classes: "bg-emerald-100 text-emerald-800") if onboarding_complete?
      return status_payload(label: "In progress", classes: "bg-indigo-100 text-indigo-800") if onboarding_in_progress?

      status_payload(label: "Start here", classes: "bg-slate-100 text-slate-700")
    end

    def onboarding_steps
      [
        build_step(
          number: 1,
          title: "Add accounts",
          description: "Create checking, savings, card, or debt accounts first, and optionally add opening balance snapshots.",
          metric: "#{pluralized_word(accounts_data.count, "account")} set up",
          state: step1_done? ? :done : :next
        ),
        build_step(
          number: 2,
          title: "Set up recurring transactions",
          description: "Save the incoming and outgoing items you expect, then link them to accounts where possible.",
          metric: "#{linked_template_total_value} of #{template_total_value} recurring transactions linked",
          state: if step2_done?
            :done
          elsif step2_started?
            :in_progress
          else
            :next
          end
        ),
        build_step(
          number: 3,
          title: "Create a month and import recurring",
          description: "Create the month, then use Plan and Edit to pull the saved recurring transactions into it.",
          metric: current_month_data ? "#{pluralized_word(current_month_entries_data.count, "entry")} in #{current_month_data.label}" : "No month created yet",
          state: if step3_done?
            :done
          elsif step3_started?
            :in_progress
          else
            :next
          end
        ),
        build_step(
          number: 4,
          title: "Adjust as the month unfolds",
          description: "Add one-off items, update amounts, and mark entries paid as you go. Some recurring items may also auto-complete when due.",
          metric: current_month_data ? "#{review_attention_count_value} items still need review" : "Review starts after month setup",
          state: if step4_done?
            :done
          elsif step4_started?
            :in_progress
          else
            :next
          end
        )
      ]
    end

    def continue_title
      current_month_data ? current_month_data.label : "No active month yet"
    end

    def continue_description
      if current_month_data
        "Jump back into the month most likely to need attention right now."
      else
        "Create a month first, then return here for faster shortcuts and review widgets."
      end
    end

    def continue_badge_label
      return "Setup needed" unless current_month_data
      return "Current month" if current_month_data.month_on == today.beginning_of_month

      "Most recent month"
    end

    def current_month_leftover_class
      current_month_data && current_month_data.calculated_leftover >= 0 ? "text-emerald-700" : "text-slate-900"
    end

    def current_month_leftover_value
      current_month_data ? helpers.number_to_currency(current_month_data.calculated_leftover) : "-"
    end

    def current_month_entries_total
      current_month_data ? current_month_entries_data.count : 0
    end

    def current_month_review_total
      current_month_data ? review_attention_count_value : 0
    end

    def continue_stats
      [
        {
          label: "Leftover",
          value: current_month_leftover_value,
          value_classes: current_month_leftover_class
        },
        {
          label: "Entries",
          value: current_month_entries_total,
          value_classes: "text-slate-900"
        },
        {
          label: "Needs review",
          value: current_month_review_total,
          value_classes: "text-slate-900"
        }
      ]
    end

    def next_step_badge
      next_step.fetch(:badge)
    end

    def next_step_title
      next_step.fetch(:title)
    end

    def next_step_description
      next_step.fetch(:description)
    end

    def next_step_primary_action
      {
        label: next_step.fetch(:primary_label),
        path: next_step.fetch(:primary_path),
        turbo_frame: next_step[:primary_turbo_frame]
      }
    end

    def next_step_secondary_action
      {
        label: next_step.fetch(:secondary_label),
        path: next_step.fetch(:secondary_path),
        turbo_frame: next_step[:secondary_turbo_frame]
      }
    end

    def cashflow_available?
      year_cashflow_payload_data[:links].any?
    end

    def cashflow_chart_title
      "#{overview_cashflow_year_value} cash flow graph"
    end

    def cashflow_stat_cards
      [
        {
          label: "Months Included",
          value: year_cashflow_payload_data[:month_count],
          value_classes: "text-slate-900"
        },
        {
          label: "Income",
          value: helpers.number_to_currency(year_cashflow_payload_data[:income_total]),
          value_classes: "text-emerald-700"
        },
        {
          label: "Outflow",
          value: helpers.number_to_currency(year_cashflow_payload_data[:outflow_total]),
          value_classes: "text-rose-700"
        },
        {
          label: "Leftover",
          value: helpers.number_to_currency(year_cashflow_payload_data[:leftover_total]),
          value_classes: year_cashflow_payload_data[:leftover_total] >= 0 ? "text-emerald-700" : "text-slate-900"
        }
      ]
    end

    def attention_queue_description
      if current_month_data
        "Counts are based on #{current_month_data.label}."
      else
        "Create a month to start surfacing review items here."
      end
    end

    def attention_queue_total
      current_month_data ? review_attention_count_value : 0
    end

    def attention_items
      [
        { label: "Still planned and due", count: due_planned_count_value },
        { label: "Missing key details", count: missing_details_count_value },
        { label: "Paid without actual", count: paid_missing_actual_count_value }
      ]
    end

    def recurring_linked_summary
      "#{linked_template_total_value} linked recurring #{linked_template_total_value == 1 ? "transaction" : "transactions"} currently connected to accounts."
    end

    def recurring_breakdown_items
      [
        {
          label: "Pay schedules",
          count: template_counts.fetch(:pay_schedules),
          path: routes.planning_templates_path(anchor: "pay-schedules")
        },
        {
          label: "Subscriptions",
          count: template_counts.fetch(:subscriptions),
          path: routes.planning_templates_path(anchor: "subscriptions")
        },
        {
          label: "Monthly bills",
          count: template_counts.fetch(:monthly_bills),
          path: routes.planning_templates_path(anchor: "monthly-bills")
        },
        {
          label: "Payment plans",
          count: template_counts.fetch(:payment_plans),
          path: routes.planning_templates_path(anchor: "payment-plans")
        }
      ]
    end

    def accounts_badge_label
      pluralized_word(accounts_data.count, "account")
    end

    def net_worth_value_class
      net_worth_total_value >= 0 ? "text-slate-900" : "text-rose-700"
    end

    def latest_snapshot_date_label
      latest_snapshot_data ? I18n.l(latest_snapshot_data.recorded_on, format: :long) : "No snapshots yet"
    end

    def latest_snapshot_subtitle
      latest_snapshot_data ? latest_snapshot_data.account.name : "Add an account balance to start tracking."
    end

    def account_snapshot_cards
      [
        {
          label: "Net worth",
          value: helpers.number_to_currency(net_worth_total_value),
          value_classes: net_worth_value_class
        },
        {
          label: "Latest snapshot",
          value: latest_snapshot_date_label,
          value_classes: "text-slate-900",
          value_size_classes: "text-sm",
          subtitle: latest_snapshot_subtitle
        }
      ]
    end

    def linked_entries_summary
      "#{linked_entries_count_value} linked month #{linked_entries_count_value == 1 ? "entry" : "entries"} in #{current_month_data&.label || "the active month"} (#{linked_paid_entries_count_value} paid)."
    end

    def [](key)
      data[key.to_sym]
    end

    def fetch(key)
      data.fetch(key.to_sym)
    end

    def to_h
      data.dup
    end

    def method_missing(name, *args, &block)
      return data.fetch(name) if args.empty? && block.nil? && data.key?(name)

      super
    end

    def respond_to_missing?(name, include_private = false)
      data.key?(name) || super
    end

    private

    attr_reader :data, :today

    def accounts_data
      data.fetch(:accounts)
    end

    def current_month_data
      data[:current_month]
    end

    def current_month_entries_data
      data.fetch(:current_month_entries)
    end

    def template_total_value
      data.fetch(:template_total)
    end

    def linked_template_total_value
      data.fetch(:linked_template_total)
    end

    def review_attention_count_value
      data.fetch(:review_attention_count)
    end

    def linked_paid_entries_count_value
      data.fetch(:linked_paid_entries_count)
    end

    def year_cashflow_payload_data
      data.fetch(:year_cashflow_payload)
    end

    def overview_cashflow_year_value
      data.fetch(:overview_cashflow_year)
    end

    def due_planned_count_value
      data.fetch(:due_planned_count)
    end

    def missing_details_count_value
      data.fetch(:missing_details_count)
    end

    def paid_missing_actual_count_value
      data.fetch(:paid_missing_actual_count)
    end

    def net_worth_total_value
      data.fetch(:net_worth_total)
    end

    def latest_snapshot_data
      data[:latest_snapshot]
    end

    def linked_entries_count_value
      data.fetch(:linked_entries_count)
    end

    def template_counts
      data.fetch(:template_counts)
    end

    def next_step_data
      data.fetch(:next_step)
    end

    def onboarding_complete?
      step1_done? && step2_done? && step3_done? && step4_done?
    end

    def onboarding_in_progress?
      step1_done? || step2_started? || step3_started? || step4_started?
    end

    def step1_done?
      accounts_data.any?
    end

    def step2_done?
      template_total_value.positive? && linked_template_total_value == template_total_value
    end

    def step2_started?
      template_total_value.positive? || linked_template_total_value.positive?
    end

    def step3_done?
      current_month_data.present? && current_month_entries_data.any?
    end

    def step3_started?
      current_month_data.present?
    end

    def step4_done?
      current_month_entries_data.any? && (review_attention_count_value.zero? || linked_paid_entries_count_value.positive?)
    end

    def step4_started?
      current_month_entries_data.any?
    end

    def build_step(number:, title:, description:, metric:, state:)
      {
        number: number,
        title: title,
        description: description,
        metric: metric,
        card_classes: step_card_classes(state),
        badge_label: step_badge_label(state),
        badge_classes: step_badge_classes(state)
      }
    end

    def status_payload(label:, classes:)
      { label: label, classes: classes }
    end

    def step_card_classes(state)
      case state
      when :done then "border-emerald-200"
      when :in_progress then "border-indigo-200"
      else "border-slate-200"
      end
    end

    def step_badge_label(state)
      case state
      when :done then "Done"
      when :in_progress then "In progress"
      else "Next"
      end
    end

    def step_badge_classes(state)
      case state
      when :done then "bg-emerald-100 text-emerald-700"
      when :in_progress then "bg-indigo-100 text-indigo-700"
      else "bg-slate-100 text-slate-600"
      end
    end

    def pluralized_word(count, singular)
      "#{count} #{count == 1 ? singular : singular.pluralize}"
    end

    def helpers
      ApplicationController.helpers
    end

    def routes
      Rails.application.routes.url_helpers
    end

    def next_step
      next_step_data
    end
  end
end
