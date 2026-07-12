class AccountActivityImport < ApplicationRecord
  AMOUNT_STRATEGIES = %w[charges_are_negative charges_are_positive type_column].freeze

  belongs_to :user
  belongs_to :account
  has_many :account_activities, dependent: :destroy

  validates :original_filename, :header_row_number, :amount_strategy, presence: true
  validates :amount_strategy, inclusion: { in: AMOUNT_STRATEGIES }
  validates :rows_count, :imported_count, :duplicate_count, numericality: { greater_than_or_equal_to: 0 }
  validate :account_belongs_to_user

  def institution_balance?
    institution_balance.present?
  end

  def institution_balance
    value = metadata_value("institution_balance")
    return if value.blank?

    BigDecimal(value.to_s)
  rescue ArgumentError
    nil
  end

  def institution_balance_as_of
    value = metadata_value("institution_balance_as_of")
    return if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def institution_name
    metadata_value("institution_name").presence
  end

  private

  def account_belongs_to_user
    return if account.blank? || user.blank?
    return if account.user_id == user_id

    errors.add(:account, "must belong to the same user")
  end

  def metadata_value(key)
    metadata.to_h[key.to_s] || metadata.to_h[key.to_sym]
  end
end
