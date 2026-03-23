class MonthlyBill < ApplicationRecord
  include TemplateAccountLinkable

  BILLING_MONTHS_BY_FREQUENCY = {
    "monthly" => (1..12).to_a,
    "quarterly" => [ 1, 4, 7, 10 ],
    "semiannual" => [ 1, 7 ],
    "annual" => [ 1 ]
  }.freeze

  belongs_to :user
  belongs_to :linked_account, class_name: "Account", optional: true
  template_account_association :linked_account

  enum :kind, {
    fixed_payment: 0,
    variable_bill: 1
  }
  enum :billing_frequency, {
    monthly: 0,
    quarterly: 1,
    semiannual: 2,
    annual: 3
  }

  before_validation :normalize_billing_months

  validates :name, presence: true
  validates :due_day, inclusion: { in: 1..31 }
  validate :validate_billing_months

  scope :active_only, -> { where(active: true).order(:due_day, :name) }

  def due_date_for_month(month_on)
    Date.new(month_on.year, month_on.month, [ due_day, month_on.end_of_month.day ].min)
  end

  def scheduled_for_month?(month_on)
    billing_months.include?(month_on.month)
  end

  def matches_entry?(entry, month_on:)
    return false if entry.blank? || entry.occurred_on.blank?
    return false unless scheduled_for_month?(month_on)
    return false unless comparable_text(entry.payee) == comparable_text(name)
    return false unless entry.occurred_on == due_date_for_month(month_on)

    entry.source_file == "monthly_bill" || entry.fixed? || entry.manual?
  end

  def billing_months
    super.presence || default_billing_months
  end

  def default_billing_months
    BILLING_MONTHS_BY_FREQUENCY.fetch(billing_frequency || "monthly")
  end

  private

  def normalize_billing_months
    normalized_months = Array(self[:billing_months]).reject(&:blank?).map(&:to_i).uniq.sort
    normalized_months = default_billing_months if normalized_months.empty?
    self[:billing_months] = normalized_months
  end

  def validate_billing_months
    months = Array(self[:billing_months]).map(&:to_i)

    if months.any? { |month| month < 1 || month > 12 }
      errors.add(:billing_months, "must only include valid calendar months")
    end

    expected_count = default_billing_months.size
    return if months.size == expected_count

    errors.add(:billing_months, "must include #{expected_count} month#{'s' unless expected_count == 1} for #{billing_frequency.humanize.downcase}")
  end

  def comparable_text(value)
    value.to_s.strip.downcase
  end
end
