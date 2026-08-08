module Accounts
  class TargetMovementWindow
    CARD_COLORS = {
      added: "rgba(244, 63, 94, 0.58)",
      paid: "rgba(16, 185, 129, 0.58)",
      planned: "rgba(14, 165, 233, 0.45)"
    }.freeze
    BANK_COLORS = {
      money_in: "rgba(16, 185, 129, 0.58)",
      paid_out: "rgba(244, 63, 94, 0.58)",
      left_to_pay: "rgba(245, 158, 11, 0.5)"
    }.freeze

    def initialize(workspace:, budget_months:)
      @workspace = workspace
      @budget_months = Array(budget_months).sort_by(&:month_on)
    end

    def call
      classify
      {
        account_flow_payload: account_flow_payload,
        account_movement_payload: account_movement_payload,
        calculation_version: Budgeting::PeriodSummary::CALCULATION_VERSION
      }
    end

    private

    attr_reader :budget_months, :workspace

    def periods
      @periods ||= begin
        month_ids = budget_months.map(&:id)
        mappings = workspace.legacy_record_mappings.where(
          legacy_record_type: "BudgetMonth",
          legacy_record_id: month_ids,
          target_record_type: "BudgetPeriod"
        ).pluck(:legacy_record_id, :target_record_id).to_h
        periods_by_id = workspace.budget_periods.where(id: mappings.values).index_by(&:id)
        budget_months.filter_map { |month| periods_by_id[mappings[month.id]] }
      end
    end

    def month_index
      @month_index ||= periods.each_with_index.to_h { |period, index| [ period.starts_on, index ] }
    end

    def accounts
      @accounts ||= workspace.accounts.index_by(&:id)
    end

    def classify
      return if defined?(@classified)

      @actual = Hash.new { |hash, account_id| hash[account_id] = { in: zero_series, out: zero_series, transaction_ids: [] } }
      postings.each do |account_id, amount, effective_on, transaction_id|
        index = month_index[effective_on.beginning_of_month]
        next if index.blank?

        amount = amount.to_d
        @actual[account_id][amount.negative? ? :out : :in][index] += amount.abs
        @actual[account_id][:transaction_ids] << transaction_id
      end
      @planned = Hash.new { |hash, account_id| hash[account_id] = zero_series }
      active_items.each do |item|
        index = month_index.fetch(item.budget_period.starts_on)
        remaining = remaining_amount(item)
        next unless remaining.positive?

        if item.intended_source_account_id.present? && !accounts[item.intended_source_account_id]&.credit_card?
          @planned[item.intended_source_account_id][index] += remaining
        end
        if item.intended_destination_account_id.present? && accounts[item.intended_destination_account_id]&.credit_card?
          @planned[item.intended_destination_account_id][index] += remaining
        end
      end
      @classified = true
    end

    def postings
      return [] if periods.empty?

      workspace.account_postings
        .joins(:financial_transaction)
        .where(financial_transactions: { state: "posted", effective_on: periods.first.starts_on..periods.last.starts_on.end_of_month })
        .pluck(:account_id, :amount, "financial_transactions.effective_on", :financial_transaction_id)
    end

    def active_items
      @active_items ||= workspace.budget_items
        .where(budget_period_id: periods.map(&:id))
        .where.not(state: %w[skipped cancelled voided])
        .includes(:budget_period)
        .to_a
    end

    def allocation_totals
      @allocation_totals ||= workspace.budget_allocations
        .joins(:financial_transaction)
        .where(budget_item_id: active_items.map(&:id), financial_transactions: { state: "posted" })
        .group(:budget_item_id)
        .sum(:amount)
    end

    def remaining_amount(item)
      [ item.planned_amount - allocation_totals.fetch(item.id, 0).to_d, 0 ].max
    end

    def account_flow_payload
      rows = @actual.filter_map do |account_id, values|
        account = accounts[account_id]
        next if account.blank?

        {
          id: account.id,
          name: account.name,
          charged_total: values[:out].sum,
          paid_total: values[:in].sum,
          transaction_ids: values[:transaction_ids].uniq
        }
      end.sort_by { |row| -(row[:charged_total] + row[:paid_total]) }
      {
        labels: rows.map { |row| row[:name] },
        charged_values: rows.map { |row| row[:charged_total].to_f.round(2) },
        paid_values: rows.map { |row| row[:paid_total].to_f.round(2) },
        charged_total: rows.sum { |row| row[:charged_total] }.round(2),
        paid_total: rows.sum { |row| row[:paid_total] }.round(2),
        account_count: rows.size,
        tracked_entries_count: rows.flat_map { |row| row[:transaction_ids] }.uniq.size,
        untracked_entries_count: untracked_transaction_count,
        top_account: rows.first
      }
    end

    def account_movement_payload
      card_ids = accounts.values.select(&:credit_card?).map(&:id)
      bank_ids = accounts.keys - card_ids
      {
        month_labels: periods.map { |period| period.starts_on.strftime("%b %Y") },
        credit_card: {
          datasets: datasets(card_ids, [ [ :out, "added", CARD_COLORS[:added] ], [ :in, "paid off", CARD_COLORS[:paid] ], [ :planned, "planned payments", CARD_COLORS[:planned] ] ]),
          added_total: total(card_ids, :out),
          paid_total: total(card_ids, :in),
          planned_payment_total: total(card_ids, :planned),
          account_count: active_account_count(card_ids),
          drilldowns: []
        },
        bank_accounts: {
          datasets: datasets(bank_ids, [ [ :in, "money in", BANK_COLORS[:money_in] ], [ :out, "paid out", BANK_COLORS[:paid_out] ], [ :planned, "left to pay", BANK_COLORS[:left_to_pay] ] ]),
          money_in_total: total(bank_ids, :in),
          paid_out_total: total(bank_ids, :out),
          left_to_pay_total: total(bank_ids, :planned),
          account_count: active_account_count(bank_ids),
          drilldowns: []
        }
      }
    end

    def datasets(account_ids, definitions)
      account_ids.sort_by { |id| accounts.fetch(id).name }.flat_map do |account_id|
        definitions.filter_map do |key, label, color|
          values = series(account_id, key).map { |value| value.to_f.round(2) }
          next if values.all?(&:zero?)

          { label: "#{accounts.fetch(account_id).name} #{label}", data: values, backgroundColor: color }
        end
      end
    end

    def series(account_id, key)
      key == :planned ? @planned[account_id] : @actual[account_id][key]
    end

    def total(account_ids, key)
      account_ids.sum { |account_id| series(account_id, key).sum }.to_f.round(2)
    end

    def active_account_count(account_ids)
      account_ids.count do |account_id|
        %i[in out planned].any? { |key| series(account_id, key).any?(&:positive?) }
      end
    end

    def untracked_transaction_count
      return 0 if periods.empty?

      workspace.financial_transactions
        .where(state: "posted", effective_on: periods.first.starts_on..periods.last.starts_on.end_of_month)
        .where.missing(:account_postings)
        .count
    end

    def zero_series
      Array.new(periods.size, 0.to_d)
    end
  end
end
