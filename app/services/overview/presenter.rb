module Overview
  class Presenter
    def initialize(user:, today: Date.current, data: nil, account_flow_month_window: Overview::AccountFlowWindow::DEFAULT_MONTH_WINDOW)
      @today = today
      @data = data || Overview::PageData.new(
        user: user,
        today: today,
        account_flow_month_window: account_flow_month_window
      ).call
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
          action_label: step1_done? ? "Review Accounts" : "Add First Account",
          action_path: step1_done? ? routes.accounts_path : routes.new_account_path,
          state: step1_done? ? :done : :next
        ),
        build_step(
          number: 2,
          title: "Set up recurring transactions",
          description: "Save the incoming and outgoing items you expect, then link them to accounts where possible.",
          metric: "#{linked_template_total_value} of #{template_total_value} recurring transactions linked",
          action_label: step2_done? ? "Review Recurring" : "Set Up Recurring",
          action_path: routes.planning_templates_path,
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
          action_label: step3_started? ? "Open Plan and Edit" : "Create Month",
          action_path: step3_started? ? routes.budget_month_tab_path(current_month_data, "entries") : routes.new_budget_month_path,
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
          action_label: current_month_data ? "Review Month" : "Create Month",
          action_path: current_month_data ? routes.budget_month_tab_path(current_month_data, "entries") : routes.new_budget_month_path,
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

    def check_in_badge
      current_month_data ? "Weekly check-in" : "First useful step"
    end

    def check_in_title
      if current_month_data
        "Keep #{current_month_data.label} easy to trust"
      else
        "Start small, then build from there"
      end
    end

    def check_in_description
      if current_month_data && review_attention_count_value.zero?
        "No urgent review items are waiting. Use this card as a quick scan before you move on."
      elsif current_month_data
        "A short pass through these items keeps the month current without turning budgeting into a long session."
      else
        "You do not need to model everything today. Add one account, one balance, and one recurring item to make the app useful."
      end
    end

    def check_in_status
      if current_month_data.nil?
        status_payload(label: "Set up", classes: "bg-slate-100 text-slate-700")
      elsif review_attention_count_value.zero?
        status_payload(label: "On track", classes: "bg-emerald-100 text-emerald-800")
      else
        status_payload(label: "Review", classes: "bg-amber-100 text-amber-800")
      end
    end

    def check_in_win
      return nil unless current_month_data && review_attention_count_value.zero?

      {
        title: "Small win",
        description: "Your attention queue is clear for now. A quick glance at upcoming plans is enough before you move on."
      }
    end

    def check_in_items
      return setup_check_in_items unless current_month_data

      [
        check_in_item(
          label: "Due now",
          value: due_planned_count_value,
          description: "Planned entries dated today or earlier.",
          tone: due_planned_count_value.positive? ? :attention : :clear,
          path: routes.budget_month_tab_path(current_month_data, "entries")
        ),
        check_in_item(
          label: "Due next 7 days",
          value: due_soon_count_value,
          description: "Upcoming planned entries to keep on your radar.",
          tone: due_soon_count_value.positive? ? :info : :neutral,
          path: routes.budget_month_tab_path(current_month_data, "calendar")
        ),
        check_in_item(
          label: "Missing actuals",
          value: paid_missing_actual_count_value,
          description: "Paid entries that still need the real amount.",
          tone: paid_missing_actual_count_value.positive? ? :attention : :clear,
          path: routes.budget_month_tab_path(current_month_data, "entries")
        ),
        check_in_item(
          label: "Linked activity",
          value: linked_entries_count_value,
          description: "Entries connected to accounts for balances and movement.",
          tone: linked_entries_count_value.positive? ? :clear : :neutral,
          path: routes.budget_month_tab_path(current_month_data, "timeline")
        )
      ]
    end

    def financial_rhythm_label
      helpers.financial_rhythm_label(financial_rhythm_value)
    end

    def financial_rhythm_guidance
      {
        "steady_income" => "Keep recurring paychecks and fixed bills current, then use weekly check-ins to catch exceptions.",
        "variable_income" => "Review income and leftover cash more often so the month can adjust before spending decisions pile up.",
        "shared_household" => "Use clear account links and notes so shared bills, transfers, and one-off entries stay understandable later.",
        "debt_payoff" => "Watch credit card additions, paid down totals, and payoff progress before deciding how much extra to send."
      }.fetch(financial_rhythm_value)
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
          value_classes: current_month_review_total.zero? ? "text-emerald-700" : "text-slate-900"
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
        return "#{current_month_data.label} has no urgent cleanup items right now." if review_attention_count_value.zero?

        "Counts are based on #{current_month_data.label}."
      else
        "Create a month to start surfacing review items here."
      end
    end

    def attention_queue_total
      current_month_data ? review_attention_count_value : 0
    end

    def attention_queue_badge
      return status_payload(label: "0", classes: "bg-slate-100 text-slate-600") unless current_month_data
      return status_payload(label: "Clear", classes: "bg-emerald-100 text-emerald-800") if review_attention_count_value.zero?

      status_payload(label: attention_queue_total, classes: "bg-amber-100 text-amber-800")
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

    def account_flow_month_window
      data.fetch(:account_flow_month_window)
    end

    def account_flow_month_window_options
      Overview::AccountFlowWindow::MONTH_WINDOW_OPTIONS
    end

    def account_flow_available?
      account_flow_payload_data[:account_count].positive?
    end

    def account_flow_summary_title
      "Linked account activity"
    end

    def account_flow_summary_description
      return "Select saved months to compare where entries happen and where payments or deposits land." if account_flow_months_included_value.zero?

      "#{pluralized_word(account_flow_months_included_value, "month")} included: #{account_flow_month_range_label_value}."
    end

    def account_flow_stat_cards
      [
        {
          label: "Charged",
          value: helpers.number_to_currency(account_flow_payload_data[:charged_total]),
          value_classes: "text-rose-700"
        },
        {
          label: "Paid to",
          value: helpers.number_to_currency(account_flow_payload_data[:paid_total]),
          value_classes: "text-emerald-700"
        },
        {
          label: "Tracked entries",
          value: account_flow_payload_data[:tracked_entries_count],
          value_classes: "text-slate-900"
        }
      ]
    end

    def account_flow_chart_title
      "Linked Activity by Account"
    end

    def account_flow_top_account_summary
      account_flow_payload_data[:top_account] && "Top activity: #{account_flow_payload_data[:top_account][:name]}"
    end

    def account_flow_untracked_entries_summary
      return nil unless account_flow_payload_data[:untracked_entries_count].positive?

      "#{pluralized_word(account_flow_payload_data[:untracked_entries_count], "entry")} missing account detail"
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

    def due_soon_count_value
      data.fetch(:due_soon_count, 0)
    end

    def net_worth_total_value
      data.fetch(:net_worth_total)
    end

    def latest_snapshot_data
      data[:latest_snapshot]
    end

    def financial_rhythm_value
      data.fetch(:financial_rhythm, "steady_income")
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

    def account_flow_payload_data
      data.fetch(:account_flow_payload)
    end

    def account_flow_months_included_value
      data.fetch(:account_flow_months_included)
    end

    def account_flow_month_range_label_value
      data.fetch(:account_flow_month_range_label)
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

    def build_step(number:, title:, description:, metric:, action_label:, action_path:, state:)
      {
        number: number,
        title: title,
        description: description,
        metric: metric,
        action_label: action_label,
        action_path: action_path,
        card_classes: step_card_classes(state),
        badge_label: step_badge_label(state),
        badge_classes: step_badge_classes(state)
      }
    end

    def setup_check_in_items
      [
        check_in_item(
          label: "Accounts",
          value: accounts_data.count,
          description: "Add one real account so future entries have context.",
          tone: accounts_data.any? ? :clear : :neutral,
          path: accounts_data.any? ? routes.accounts_path : routes.new_account_path
        ),
        check_in_item(
          label: "Snapshots",
          value: latest_snapshot_data.present? ? 1 : 0,
          description: "A first snapshot gives balances a trusted starting point.",
          tone: latest_snapshot_data.present? ? :clear : :neutral,
          path: accounts_data.any? ? routes.accounts_path : routes.new_account_path
        ),
        check_in_item(
          label: "Recurring",
          value: template_total_value,
          description: "Save one repeated paycheck, bill, subscription, or payment.",
          tone: template_total_value.positive? ? :clear : :neutral,
          path: routes.planning_templates_path
        ),
        check_in_item(
          label: "First month",
          value: current_month_data ? 1 : 0,
          description: "Create a month when the first few building blocks are ready.",
          tone: current_month_data ? :clear : :neutral,
          path: current_month_data ? routes.budget_month_path(current_month_data) : routes.new_budget_month_path
        )
      ]
    end

    def check_in_item(label:, value:, description:, tone:, path:)
      {
        label: label,
        value: value,
        description: description,
        path: path,
        card_classes: check_in_card_classes(tone),
        value_classes: check_in_value_classes(tone)
      }
    end

    def check_in_card_classes(tone)
      {
        attention: "border-amber-200 bg-amber-50/80",
        clear: "border-emerald-200 bg-emerald-50/70",
        info: "border-sky-200 bg-sky-50/70",
        neutral: "border-slate-200 bg-white/85"
      }.fetch(tone)
    end

    def check_in_value_classes(tone)
      {
        attention: "text-amber-800",
        clear: "text-emerald-700",
        info: "text-sky-700",
        neutral: "text-slate-900"
      }.fetch(tone)
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
