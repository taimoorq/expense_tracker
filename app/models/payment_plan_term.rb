class PaymentPlanTerm < ApplicationRecord
  self.primary_key = :planning_template_id

  belongs_to :planning_template

  validates :total_due, numericality: { greater_than: 0 }
  validates :opening_paid_adjustment, numericality: { greater_than_or_equal_to: 0 }
  validates :monthly_target, numericality: { greater_than_or_equal_to: 0 }
  validate :opening_adjustment_within_total

  private

  def opening_adjustment_within_total
    return if total_due.blank? || opening_paid_adjustment.blank? || opening_paid_adjustment <= total_due

    errors.add(:opening_paid_adjustment, "cannot exceed total due")
  end
end
