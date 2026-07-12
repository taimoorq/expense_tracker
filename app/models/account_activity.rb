class AccountActivity < ApplicationRecord
  belongs_to :user
  belongs_to :account
  belongs_to :account_activity_import
  belongs_to :expense_entry, optional: true

  before_validation :assign_user_from_account

  validates :transaction_on, :description, :row_number, :fingerprint, presence: true
  validates :amount, numericality: { greater_than_or_equal_to: 0 }
  validates :raw_amount, :account_delta, numericality: true
  validates :fingerprint, uniqueness: { scope: :account_id }
  validate :account_belongs_to_user
  validate :import_belongs_to_account_and_user
  validate :expense_entry_belongs_to_user

  scope :recent_first, -> { order(transaction_on: :desc, created_at: :desc) }

  private

  def assign_user_from_account
    self.user ||= account&.user
  end

  def account_belongs_to_user
    return if account.blank? || user.blank?
    return if account.user_id == user_id

    errors.add(:account, "must belong to the same user")
  end

  def import_belongs_to_account_and_user
    return if account_activity_import.blank?

    if account.present? && account_activity_import.account_id != account_id
      errors.add(:account_activity_import, "must belong to the same account")
    end

    return if user.blank? || account_activity_import.user_id == user_id

    errors.add(:account_activity_import, "must belong to the same user")
  end

  def expense_entry_belongs_to_user
    return if expense_entry.blank? || user.blank?
    return if expense_entry.user_id == user_id

    errors.add(:expense_entry, "must belong to the same user")
  end
end
