class MonthlyBill < ApplicationRecord
  include TemplateAccountLinkable

  belongs_to :user
  belongs_to :linked_account, class_name: "Account", optional: true
  template_account_association :linked_account

  enum :kind, {
    fixed_payment: 0,
    variable_bill: 1
  }

  validates :name, presence: true
  validates :due_day, inclusion: { in: 1..31 }

  scope :active_only, -> { where(active: true).order(:due_day, :name) }

  def due_date_for_month(month_on)
    Date.new(month_on.year, month_on.month, [ due_day, month_on.end_of_month.day ].min)
  end

  def matches_entry?(entry, month_on:)
    return false if entry.blank? || entry.occurred_on.blank?
    return false unless comparable_text(entry.payee) == comparable_text(name)
    return false unless entry.occurred_on == due_date_for_month(month_on)

    entry.source_file == "monthly_bill" || entry.fixed? || entry.manual?
  end

  private

  def comparable_text(value)
    value.to_s.strip.downcase
  end
end
