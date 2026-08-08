module Overview
  class TargetReviewSummary
    def self.call(period:, today: Date.current)
      new(period: period, today: today).call
    end

    def initialize(period:, today:)
      @period = period
      @today = today.to_date
    end

    def call
      counts = {
        due: due_items.size,
        missing_details: missing_detail_items.size,
        missing_actual: 0,
        auto_completed: 0
      }
      {
        due_planned_count: counts.fetch(:due),
        due_soon_count: due_soon_items.size,
        missing_details_count: counts.fetch(:missing_details),
        paid_missing_actual_count: counts.fetch(:missing_actual),
        auto_completed_count: counts.fetch(:auto_completed),
        review_attention_count: counts.values.sum,
        manual_entries_count: active_items.count(&:origin_kind_manual?),
        linked_entries_count: active_items.count { |item| item.intended_source_account_id.present? },
        linked_paid_entries_count: active_items.count do |item|
          item.intended_source_account_id.present? && allocated_amount(item).positive?
        end,
        calculation_version: Budgeting::PeriodSummary::CALCULATION_VERSION
      }
    end

    private

    attr_reader :period, :today

    def active_items
      @active_items ||= period.budget_items
        .where.not(state: %w[skipped cancelled voided])
        .to_a
    end

    def allocation_totals
      @allocation_totals ||= period.budget_workspace.budget_allocations
        .joins(:financial_transaction)
        .where(budget_item_id: active_items.map(&:id), financial_transactions: { state: "posted" })
        .group(:budget_item_id)
        .sum(:amount)
    end

    def allocated_amount(item)
      allocation_totals.fetch(item.id, 0.to_d).to_d
    end

    def remaining_amount(item)
      [ item.planned_amount - allocated_amount(item), 0.to_d ].max
    end

    def due_items
      @due_items ||= active_items.select do |item|
        item.scheduled_on.present? && item.scheduled_on <= today && remaining_amount(item).positive?
      end
    end

    def due_soon_items
      @due_soon_items ||= active_items.select do |item|
        item.scheduled_on.present? && item.scheduled_on > today && item.scheduled_on <= today + 7.days &&
          remaining_amount(item).positive?
      end
    end

    def missing_detail_items
      @missing_detail_items ||= active_items.select do |item|
        item.scheduled_on.blank? || item.category_snapshot.blank? || item.payee_snapshot.blank?
      end
    end
  end
end
