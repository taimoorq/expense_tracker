class PaymentPlan < ApplicationRecord
  include PlanningTemplateMetadata
  include RecurringEntryTemplate
  include TemplateAccountLinkable

  belongs_to :user
  belongs_to :linked_account, class_name: "Account", optional: true
  template_account_association :linked_account
  planning_template_metadata(
    type_key: :payment_plan,
    source_file: "payment_plan",
    param_key: :payment_plan,
    recurring_source: true,
    wizard_sections: %w[debt manual],
    permitted_attributes: [ :name, :total_due, :amount_paid, :monthly_target, :due_day, :linked_account_id, :account, :active, :notes ]
  )

  validates :name, presence: true
  validates :total_due, presence: true
  validates :amount_paid, presence: true
  validates :due_day, inclusion: { in: 1..31 }

  scope :active_only, -> { where(active: true).order(:due_day, :name) }

  def remaining_balance
    [ total_due - amount_paid, 0 ].max
  end

  def monthly_amount
    target = monthly_target.presence || remaining_balance
    [ target, remaining_balance ].min
  end

  def due_date_for_month(month_on)
    Date.new(month_on.year, month_on.month, [ due_day, month_on.end_of_month.day ].min)
  end

  def matches_entry?(entry, month_on:)
    matches_entry_for_month?(entry, month_on: month_on)
  end

  def apply_payment!(amount)
    return if amount.to_d <= 0

    update!(amount_paid: amount_paid + amount)
    update!(active: false) if remaining_balance <= 0
  end

  def recurring_month_occurrences(month_on)
    return [] if monthly_amount.to_d <= 0

    [ due_date_for_month(month_on) ]
  end

  private

  def generated_entry_amount(month_on:, occurred_on:)
    monthly_amount
  end

  def generated_entry_section
    :debt
  end

  def generated_entry_category
    "Payment Plan"
  end

  def generated_entry_notes(month_on:, occurred_on:)
    "Remaining: #{remaining_balance.to_f}"
  end

  def strict_matching_amount?
    true
  end
end
