class RecurringOccurrence < ApplicationRecord
  enum :state, {
    pending: "pending",
    materialized: "materialized",
    skipped: "skipped",
    cancelled: "cancelled",
    failed: "failed"
  }, prefix: true

  belongs_to :budget_workspace
  belongs_to :planning_template
  belongs_to :budget_period
  belongs_to :budget_item, optional: true
  belongs_to :generation_operation, class_name: "OperationRun", optional: true

  validates :scheduled_on, :slot_key, presence: true
  validates :slot_key, uniqueness: { scope: %i[planning_template_id budget_period_id scheduled_on] }
  validate :materialized_state_is_coherent

  private

  def materialized_state_is_coherent
    return if state_materialized? == budget_item_id.present?

    errors.add(:budget_item, state_materialized? ? "is required when materialized" : "must be blank unless materialized")
  end
end
