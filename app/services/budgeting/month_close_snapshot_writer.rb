module Budgeting
  class MonthCloseSnapshotWriter
    Result = Data.define(:item_count, :transaction_count)

    def self.call(month_close:)
      new(month_close: month_close).call
    end

    def initialize(month_close:)
      @month_close = month_close
      @period = month_close.budget_period
      @workspace = month_close.budget_workspace
    end

    def call
      raise ArgumentError, "The close and period must share a workspace." unless period.budget_workspace_id == workspace.id

      item_rows = build_item_rows
      transaction_rows = build_transaction_rows
      MonthCloseItemSnapshot.insert_all!(item_rows) if item_rows.any?
      MonthCloseTransactionSnapshot.insert_all!(transaction_rows) if transaction_rows.any?
      verify_summary!(item_rows)

      Result.new(item_count: item_rows.size, transaction_count: transaction_rows.size)
    end

    private

    attr_reader :month_close, :period, :workspace

    def build_item_rows
      items.map do |item|
        actual = item_allocation_totals.fetch(item.id, 0.to_d)
        {
          budget_workspace_id: workspace.id,
          month_close_id: month_close.id,
          budget_item_id: item.id,
          flow_kind: item.flow_kind,
          budget_group: item.budget_group,
          name_snapshot: item.name_snapshot.presence || item.payee_snapshot.presence || item.category_snapshot,
          category_snapshot: item.category&.name.presence || item.category_snapshot,
          scheduled_on: item.scheduled_on,
          planned_amount: item.planned_amount,
          actual_amount: actual,
          remaining_amount: [ item.planned_amount - actual, 0 ].max,
          currency_code: item.currency_code,
          created_at: timestamp,
          updated_at: timestamp
        }
      end
    end

    def build_transaction_rows
      transactions.map do |transaction|
        {
          budget_workspace_id: workspace.id,
          month_close_id: month_close.id,
          financial_transaction_id: transaction.id,
          flow_kind: transaction.flow_kind,
          origin_kind: transaction.origin_kind,
          description_snapshot: transaction.description,
          category_snapshot: transaction.category&.name.presence || "Uncategorized",
          effective_on: transaction.effective_on,
          gross_amount: transaction.gross_amount,
          allocated_amount: transaction_allocation_totals.fetch(transaction.id, 0.to_d),
          currency_code: transaction.currency_code,
          created_at: timestamp,
          updated_at: timestamp
        }
      end
    end

    def items
      @items ||= period.budget_items
        .where.not(state: %w[skipped cancelled voided])
        .includes(:category)
        .order(:scheduled_on, :id)
        .to_a
    end

    def transactions
      @transactions ||= workspace.financial_transactions
        .state_posted
        .where(effective_on: period.starts_on..period.starts_on.end_of_month)
        .includes(:category)
        .order(:effective_on, :id)
        .to_a
    end

    def item_allocation_totals
      @item_allocation_totals ||= workspace.budget_allocations
        .joins(:financial_transaction)
        .where(budget_item_id: items.map(&:id), financial_transactions: { state: "posted" })
        .group(:budget_item_id)
        .sum(:amount)
    end

    def transaction_allocation_totals
      @transaction_allocation_totals ||= workspace.budget_allocations
        .where(financial_transaction_id: transactions.map(&:id))
        .group(:financial_transaction_id)
        .sum(:amount)
    end

    def verify_summary!(item_rows)
      totals = item_rows.each_with_object(Hash.new(0.to_d)) do |row, result|
        result[row.fetch(:flow_kind)] += row.fetch(:actual_amount)
      end
      return if totals["income"] == month_close.actual_income && totals["outflow"] == month_close.actual_outflow

      raise SummaryMismatch, "The close line snapshots do not match the frozen actual totals."
    end

    def timestamp
      @timestamp ||= Time.current
    end

    class SummaryMismatch < StandardError; end
  end
end
