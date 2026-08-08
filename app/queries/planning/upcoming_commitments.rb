module Planning
  class UpcomingCommitments
    WINDOW_DAYS = 90

    Row = Data.define(
      :scheduled_on, :template_id, :name, :kind, :flow_kind, :amount,
      :source_account, :destination_account, :materialized
    )
    Week = Data.define(:starts_on, :ends_on, :income, :outflow, :transfer, :rows)
    Result = Data.define(
      :starts_on, :ends_on, :rows, :weeks, :currency_code, :calculation_version, :maximum_week_total
    )

    def self.call(workspace:, starts_on: Date.current, days: WINDOW_DAYS)
      new(workspace: workspace, starts_on: starts_on, days: days).call
    end

    def initialize(workspace:, starts_on:, days:)
      @workspace = workspace
      @starts_on = starts_on.to_date
      @ends_on = @starts_on + days.to_i.days
    end

    def call
      schedule_rows = build_rows.sort_by { |row| [ row.scheduled_on, row.name.downcase, row.template_id ] }
      week_rows = weeks(schedule_rows)
      Result.new(
        starts_on: starts_on,
        ends_on: ends_on,
        rows: schedule_rows,
        weeks: week_rows,
        currency_code: workspace.default_currency_code,
        calculation_version: Budgeting::PeriodSummary::CALCULATION_VERSION,
        maximum_week_total: week_rows.map { |week| week.income + week.outflow }.max || 0.to_d
      )
    end

    private

    attr_reader :ends_on, :starts_on, :workspace

    def templates
      @templates ||= workspace.planning_templates
        .active
        .includes(
          :source_account,
          :destination_account,
          :payment_plan_term,
          :credit_card_payment_policy,
          recurrence_rule: :recurrence_months
        )
        .to_a
    end

    def build_rows
      remaining_by_template = templates.index_with { |template| payment_plan_remaining(template) }
      templates.flat_map do |template|
        scheduled_occurrences(template).filter_map do |scheduled|
          next unless scheduled.scheduled_on.between?(starts_on, ends_on)
          next unless template_active_on?(template, scheduled.scheduled_on)

          amount = occurrence_amount(template, remaining_by_template)
          next unless amount.positive?

          Row.new(
            scheduled_on: scheduled.scheduled_on,
            template_id: template.id,
            name: template.name,
            kind: template.kind,
            flow_kind: template.flow_kind,
            amount: amount,
            source_account: template.source_account,
            destination_account: template.destination_account,
            materialized: materialized_keys.include?([ template.id, scheduled.scheduled_on ])
          )
        end
      end
    end

    def scheduled_occurrences(template)
      month_starts.flat_map do |month_on|
        period = BudgetPeriod.new(
          budget_workspace: workspace,
          starts_on: month_on,
          currency_code: workspace.default_currency_code
        )
        if template.recurrence_rule.present?
          Planning::OccurrenceSchedule.call(rule: template.recurrence_rule, period: period)
        elsif template.kind_credit_card_payment? && template.credit_card_payment_policy.present?
          policy = template.credit_card_payment_policy
          date = Date.new(month_on.year, month_on.month, [ policy.due_day, month_on.end_of_month.day ].min)
          [ Planning::OccurrenceSchedule::Occurrence.new(scheduled_on: date, slot_key: "credit-card-payment") ]
        else
          []
        end
      end
    end

    def month_starts
      @month_starts ||= begin
        months = []
        cursor = starts_on.beginning_of_month
        while cursor <= ends_on.beginning_of_month
          months << cursor
          cursor = cursor.next_month
        end
        months
      end
    end

    def template_active_on?(template, date)
      return false if template.active_from.present? && date < template.active_from
      return false if template.active_until.present? && date > template.active_until

      true
    end

    def occurrence_amount(template, remaining_by_template)
      if template.kind_payment_plan? && template.payment_plan_term.present?
        remaining = remaining_by_template.fetch(template)
        amount = [ template.payment_plan_term.monthly_target, remaining ].min
        remaining_by_template[template] = [ remaining - amount, 0.to_d ].max
        amount
      elsif template.kind_credit_card_payment? && template.credit_card_payment_policy.present?
        template.credit_card_payment_policy.minimum_payment
      else
        template.default_amount
      end
    end

    def payment_plan_remaining(template)
      return template.default_amount unless template.kind_payment_plan? && template.payment_plan_term.present?

      term = template.payment_plan_term
      [ term.total_due - term.opening_paid_adjustment - allocated_progress.fetch(template.id, 0.to_d), 0.to_d ].max
    end

    def allocated_progress
      @allocated_progress ||= workspace.budget_allocations
        .joins(:financial_transaction, budget_item: :recurring_occurrence)
        .where(
          recurring_occurrences: { planning_template_id: templates.map(&:id) },
          financial_transactions: { state: "posted" }
        )
        .group("recurring_occurrences.planning_template_id")
        .sum(:amount)
    end

    def materialized_keys
      @materialized_keys ||= workspace.recurring_occurrences
        .where(planning_template_id: templates.map(&:id), scheduled_on: starts_on..ends_on, state: "materialized")
        .pluck(:planning_template_id, :scheduled_on)
        .to_set
    end

    def weeks(rows)
      first_week = starts_on.beginning_of_week
      last_week = ends_on.beginning_of_week
      weeks = []
      cursor = first_week
      while cursor <= last_week
        week_rows = rows.select { |row| row.scheduled_on.between?([ cursor, starts_on ].max, [ cursor.end_of_week, ends_on ].min) }
        totals = week_rows.group_by(&:flow_kind).transform_values { |group| group.sum(&:amount) }
        weeks << Week.new(
          starts_on: [ cursor, starts_on ].max,
          ends_on: [ cursor.end_of_week, ends_on ].min,
          income: totals.fetch("income", 0.to_d),
          outflow: totals.fetch("outflow", 0.to_d),
          transfer: totals.fetch("transfer", 0.to_d),
          rows: week_rows
        )
        cursor = cursor.next_week
      end
      weeks
    end
  end
end
