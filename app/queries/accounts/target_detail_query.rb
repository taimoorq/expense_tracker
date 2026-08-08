module Accounts
  class TargetDetailQuery
    MAX_HISTORY_MONTHS = 120

    PostingRow = Data.define(
      :transaction_id, :effective_on, :amount, :description, :flow_kind, :origin_kind
    )
    PlanRow = Data.define(
      :budget_item_id, :scheduled_on, :source_account_id, :destination_account_id,
      :flow_kind, :planned_amount, :allocated_amount
    ) do
      def remaining_amount
        [ planned_amount.to_d - allocated_amount.to_d, 0.to_d ].max
      end
    end

    def self.call(account:, as_of: Date.current, range: Accounts::MovementWindow::DEFAULT_RANGE)
      new(account: account, as_of: as_of, range: range).call
    end

    def initialize(account:, as_of:, range:)
      @account = account
      @workspace = account.budget_workspace
      @as_of = as_of.to_date
      @range = range
    end

    def call
      raise ArgumentError, "target reads are not enabled for this account" unless workspace&.target_reads_enabled?

      {
        balance_summary: balance_summary,
        movement_timeline: movement_timeline,
        balance_history_rows: balance_history_rows,
        credit_card_progress: credit_card_progress,
        reconciliation_bridge: reconciliation_bridge,
        recent_activity: { canonical_rows: posting_rows.first(5) },
        calculation_version: Budgeting::PeriodSummary::CALCULATION_VERSION
      }
    end

    private

    attr_reader :account, :as_of, :range, :workspace

    def balance_summary
      @balance_summary ||= Accounts::TargetBalanceResolver.new(account: account, as_of: as_of).call.to_h
    end

    def observations
      @observations ||= account.balance_observations
        .trusted
        .where(effective_through_at: ..as_of.end_of_day)
        .order(:effective_through_at, :created_at)
        .to_a
    end

    def posting_rows
      @posting_rows ||= account.account_postings
        .joins(financial_transaction: :budget_workspace)
        .where(financial_transactions: { state: "posted", effective_on: ..as_of })
        .order("financial_transactions.effective_on DESC", "financial_transactions.created_at DESC")
        .pluck(
          :financial_transaction_id,
          "financial_transactions.effective_on",
          :amount,
          "financial_transactions.description",
          "financial_transactions.flow_kind",
          "financial_transactions.origin_kind"
        )
        .map { |attributes| PostingRow.new(*attributes) }
    end

    def chronological_postings
      @chronological_postings ||= posting_rows.reverse
    end

    def plan_rows
      @plan_rows ||= begin
        rows = workspace.budget_items
          .where(state: "open")
          .where.not(scheduled_on: nil)
          .where(
            "intended_source_account_id = :id OR intended_destination_account_id = :id",
            id: account.id
          )
          .where(scheduled_on: ..as_of.end_of_month)
          .pluck(
            :id, :scheduled_on, :intended_source_account_id, :intended_destination_account_id,
            :flow_kind, :planned_amount
          )
        totals = workspace.budget_allocations
          .joins(:financial_transaction)
          .where(budget_item_id: rows.map(&:first), financial_transactions: { state: "posted" })
          .group(:budget_item_id)
          .sum(:amount)

        rows.map do |id, scheduled_on, source_id, destination_id, flow_kind, planned_amount|
          PlanRow.new(
            id,
            scheduled_on,
            source_id,
            destination_id,
            flow_kind,
            planned_amount,
            totals.fetch(id, 0.to_d)
          )
        end
      end
    end

    def movement_window
      @movement_window ||= Accounts::MovementWindow.new(
        range: range,
        as_of: as_of,
        earliest_on: earliest_evidence_on
      )
    end

    def earliest_evidence_on
      [
        observations.first&.effective_through_at&.to_date,
        chronological_postings.first&.effective_on,
        plan_rows.map(&:scheduled_on).min,
        as_of
      ].compact.min
    end

    def movement_timeline
      {
        range: movement_window.range,
        range_label: movement_window.range_label,
        range_options: Accounts::MovementWindow::RANGE_OPTIONS,
        starts_on: movement_window.starts_on,
        ends_on: as_of,
        bucket_unit: movement_window.bucket_unit,
        target_mode: true,
        calculation_version: Budgeting::PeriodSummary::CALCULATION_VERSION,
        buckets: movement_window.bucket_ranges.map { |bucket_range| movement_bucket(bucket_range) }
      }
    end

    def movement_bucket(bucket_range)
      starts_on = bucket_range.begin
      ends_on = bucket_range.end
      actual_through_on = [ ends_on, as_of ].min
      actuals = postings_between(starts_on, actual_through_on)
      plans = plans_between(starts_on, ends_on)
      balance = balance_on(actual_through_on)
      source = actuals.any? ? :canonical_postings : :none

      {
        label: bucket_label(starts_on, ends_on),
        starts_on: starts_on,
        ends_on: ends_on,
        actual_through_on: actual_through_on,
        current_period: starts_on <= as_of && ends_on >= as_of,
        source: source,
        source_label: source == :none ? "No posted activity" : "Canonical posted activity",
        coverage: { status: :not_applicable, starts_on: nil, ends_on: nil },
        incoming: source == :none ? nil : actuals.select { |row| row.amount.positive? }.sum { |row| row.amount.abs },
        outgoing: source == :none ? nil : actuals.select { |row| row.amount.negative? }.sum { |row| row.amount.abs },
        net: source == :none ? nil : actuals.sum { |row| row.amount.to_d },
        planned_incoming: planned_total(plans, :incoming),
        planned_outgoing: planned_total(plans, :outgoing),
        ending_balance: display_balance(balance[:current_balance]),
        projected_balance: display_balance(balance[:projected_balance]),
        balance_available: balance[:balance_available],
        activity_count: actuals.map(&:transaction_id).uniq.size,
        drilldown: {
          starts_on: starts_on.iso8601,
          ends_on: actual_through_on.iso8601,
          account_id: account.id
        }
      }
    end

    def balance_history_rows
      history_months.map { |month_on| period_balance(month_on) }
    end

    def history_months
      first_month = earliest_evidence_on.beginning_of_month
      months = []
      cursor = first_month
      while cursor <= as_of.beginning_of_month
        months << cursor
        cursor = cursor.next_month
      end
      months.last(MAX_HISTORY_MONTHS)
    end

    def period_balance(month_on)
      period_end = [ month_on.end_of_month, as_of ].min
      observation = observation_on(period_end)
      return unavailable_period(month_on, period_end) if observation.blank?

      source_on = observation.effective_through_at.to_date
      starting_through = [ month_on.prev_day, period_end ].min
      starting_delta = source_on < month_on ? postings_between(source_on.next_day, starting_through).sum { |row| row.amount.to_d } : 0.to_d
      activity_start = [ month_on, source_on.next_day ].max
      actuals = postings_between(activity_start, period_end)
      planned_delta = plans_between(month_on, month_on.end_of_month).sum { |item| plan_delta(item) }
      starting_balance = observation.balance.to_d + starting_delta
      paid_delta = actuals.sum { |row| row.amount.to_d }
      current_balance = starting_balance + paid_delta

      {
        month_on: month_on,
        balance_source: source_kind(observation, actuals),
        balance_source_label: source_label(observation, actuals),
        balance_source_recorded_on: source_on,
        activity_through_on: actuals.map(&:effective_on).max,
        starting_balance: starting_balance,
        paid_delta: paid_delta,
        current_balance: current_balance,
        planned_delta: planned_delta,
        projected_balance: current_balance + planned_delta,
        paid_entries_count: actuals.map(&:transaction_id).uniq.size,
        planned_entries_count: plans_between(month_on, month_on.end_of_month).size,
        balance_available: true
      }
    end

    def balance_on(date)
      observation = observation_on(date)
      return unavailable_balance if observation.blank?

      source_on = observation.effective_through_at.to_date
      actuals = postings_between(source_on.next_day, date)
      plans = plans_between([ date.next_day, as_of ].max, date.end_of_month)
      current_balance = observation.balance.to_d + actuals.sum { |row| row.amount.to_d }
      planned_delta = plans.sum { |item| plan_delta(item) }
      {
        current_balance: current_balance,
        projected_balance: current_balance + planned_delta,
        balance_available: true
      }
    end

    def credit_card_progress
      return unless account.credit_card?
      return unless balance_summary.fetch(:balance_available)

      month_actuals = postings_between(as_of.beginning_of_month, as_of)
      planned_payments = plans_between(as_of, as_of.end_of_month)
        .select { |item| plan_delta(item).positive? }
        .sum(&:remaining_amount)
      starting_debt = debt_amount(balance_summary.fetch(:base_balance))
      current_debt = debt_amount(balance_summary.fetch(:current_balance))
      projected_debt = debt_amount(balance_summary.fetch(:projected_balance))
      progress_percent = if starting_debt.zero?
        current_debt.zero? ? 100 : 0
      else
        (((starting_debt - current_debt) / starting_debt) * 100).clamp(0, 100).round
      end
      baseline = balance_summary.fetch(:balance_source_record)

      {
        month_label: as_of.strftime("%B %Y"),
        paid_down_this_month: month_actuals.select { |row| row.amount.positive? }.sum { |row| row.amount.abs },
        added_this_month: month_actuals.select { |row| row.amount.negative? }.sum { |row| row.amount.abs },
        net_paydown_this_month: month_actuals.sum { |row| row.amount.to_d },
        starting_debt: starting_debt,
        current_debt: current_debt,
        projected_debt: projected_debt,
        progress_percent: progress_percent,
        snapshot: nil,
        baseline_recorded_on: baseline.effective_through_at.to_date,
        baseline_label: balance_summary.fetch(:balance_source_label),
        snapshot_needed?: false,
        improved_since_snapshot?: progress_percent.positive?,
        planned_payment_remaining_this_month: planned_payments,
        calculation_version: Budgeting::PeriodSummary::CALCULATION_VERSION
      }
    end

    def reconciliation_bridge
      return unless balance_summary.fetch(:balance_available)

      baseline = balance_summary.fetch(:balance_source_record)
      actuals = postings_between(baseline.effective_through_at.to_date.next_day, as_of)
      incoming = actuals.select { |row| row.amount.positive? }.sum { |row| row.amount.abs }
      outgoing = actuals.select { |row| row.amount.negative? }.sum { |row| row.amount.abs }
      expected = balance_summary.fetch(:base_balance).to_d + incoming - outgoing
      {
        baseline_on: baseline.effective_through_at.to_date,
        through_on: as_of,
        baseline_label: balance_summary.fetch(:balance_source_label),
        baseline_balance: display_balance(balance_summary.fetch(:base_balance)),
        incoming: incoming,
        outgoing: outgoing,
        current_balance: display_balance(balance_summary.fetch(:current_balance)),
        transaction_count: actuals.map(&:transaction_id).uniq.size,
        reconciled: expected == balance_summary.fetch(:current_balance).to_d,
        calculation_version: Budgeting::PeriodSummary::CALCULATION_VERSION
      }
    end

    def observation_on(date)
      observations.reverse.find { |observation| observation.effective_through_at.to_date <= date }
    end

    def postings_between(starts_on, ends_on)
      return [] if starts_on > ends_on

      chronological_postings.select { |row| row.effective_on.between?(starts_on, ends_on) }
    end

    def plans_between(starts_on, ends_on)
      return [] if starts_on > ends_on

      plan_rows.select { |item| item.remaining_amount.positive? && item.scheduled_on.between?(starts_on, ends_on) }
    end

    def planned_total(plans, direction)
      deltas = plans.map { |item| plan_delta(item) }
      selected = direction == :incoming ? deltas.select(&:positive?) : deltas.select(&:negative?)
      selected.sum(&:abs)
    end

    def plan_delta(item)
      delta = 0.to_d
      if item.source_account_id == account.id
        delta += item.flow_kind == "income" ? item.remaining_amount : -item.remaining_amount
      end
      delta += item.remaining_amount if item.destination_account_id == account.id
      delta
    end

    def source_kind(observation, actuals)
      return :institution_import if observation.source_kind_institution_file?
      return :imported_activity if actuals.any? { |row| row.origin_kind == "institution_import" }

      :snapshot
    end

    def source_label(observation, actuals)
      {
        institution_import: "Institution import",
        imported_activity: "Imported activity",
        snapshot: "Trusted balance observation"
      }.fetch(source_kind(observation, actuals))
    end

    def display_balance(value)
      return if value.nil?

      account.liability? ? value.to_d.abs : value.to_d
    end

    def debt_amount(balance)
      [ -balance.to_d, 0.to_d ].max
    end

    def unavailable_balance
      { current_balance: nil, projected_balance: nil, balance_available: false }
    end

    def unavailable_period(month_on, period_end)
      {
        month_on: month_on,
        period_end: period_end,
        balance_source: :none,
        balance_source_label: "No trusted balance observation",
        balance_source_recorded_on: nil,
        activity_through_on: nil,
        starting_balance: 0.to_d,
        paid_delta: 0.to_d,
        current_balance: 0.to_d,
        planned_delta: 0.to_d,
        projected_balance: 0.to_d,
        paid_entries_count: 0,
        planned_entries_count: 0,
        balance_available: false
      }
    end

    def bucket_label(starts_on, ends_on)
      case movement_window.bucket_unit
      when :day then starts_on.strftime("%b %-d")
      when :week then "#{starts_on.strftime('%b %-d')}–#{ends_on.strftime('%b %-d')}"
      when :quarter then "Q#{((starts_on.month - 1) / 3) + 1} #{starts_on.year}"
      else starts_on.strftime("%b %Y")
      end
    end
  end
end
