class ExpenseEntry < ApplicationRecord
  RECURRING_TEMPLATE_SOURCES = TemplateTypeRegistry.recurring_source_files.freeze

  belongs_to :user
  belongs_to :budget_month
  belongs_to :source_account, class_name: "Account", optional: true
  belongs_to :source_template, polymorphic: true, optional: true

  enum :section, {
    income: 0,
    fixed: 1,
    variable: 2,
    debt: 3,
    manual: 4,
    auto: 5,
    other: 6
  }

  enum :status, {
    planned: 0,
    paid: 1,
    skipped: 2
  }

  validates :section, presence: true
  validates :status, presence: true
  validate :user_matches_budget_month
  validate :source_account_belongs_to_user
  validate :source_template_matches_user

  before_validation :assign_user_from_budget_month
  before_validation :assign_source_account

  scope :chronological, -> { order(:occurred_on, :created_at) }
  scope :recurring_templates, -> { where(source_file: RECURRING_TEMPLATE_SOURCES) }
  scope :due_on_or_before, ->(date) { where(occurred_on: ..date) }

  def effective_amount
    actual_amount.presence || planned_amount.presence || 0
  end

  def cashflow_amount
    income? ? effective_amount : -effective_amount
  end

  def auto_completable_recurring?
    planned? && source_file.in?(RECURRING_TEMPLATE_SOURCES) && occurred_on.present? && occurred_on <= Date.current
  end

  def account_name
    source_account&.name.presence || account
  end

  private

  def assign_user_from_budget_month
    self.user ||= budget_month&.user
  end

  def user_matches_budget_month
    return if user.blank? || budget_month.blank?
    return if user_id == budget_month.user_id

    errors.add(:user, "must match the budget month owner")
  end

  def assign_source_account
    self.source_account = resolved_source_account
    self.account = source_account.name if source_account.present? && account.blank?
  end

  def resolved_source_account
    return source_account if source_account.present?

    linked_template_account = source_template_account
    return linked_template_account if linked_template_account.present?
    return nil if user.blank? || account.blank?

    user.accounts.find_by(name: account)
  end

  def source_template_account
    return nil if source_template.blank?
    return source_template.linked_account if source_template.respond_to?(:linked_account)
    return source_template.payment_account if source_template.respond_to?(:payment_account)

    nil
  end

  def source_account_belongs_to_user
    return if source_account.blank?
    return if source_account.user_id == user_id

    errors.add(:source_account, "must belong to the same user")
  end

  def source_template_matches_user
    return if source_template.blank?
    return unless source_template.respond_to?(:user_id)
    return if source_template.user_id == user_id

    errors.add(:source_template, "must belong to the same user")
  end
end
