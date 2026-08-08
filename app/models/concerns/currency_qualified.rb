module CurrencyQualified
  extend ActiveSupport::Concern

  included do
    validates :currency_code, presence: true, format: { with: /\A[A-Z]{3}\z/ }
    validate :currency_matches_workspace
  end

  private

  def currency_matches_workspace
    return if currency_code.blank? || budget_workspace.blank?
    return if currency_code == budget_workspace.default_currency_code

    errors.add(:currency_code, "must match the workspace currency")
  end
end
