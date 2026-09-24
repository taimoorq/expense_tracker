class ProviderBalance < ApplicationRecord
  belongs_to :budget_workspace
  belongs_to :connected_account
  belongs_to :bank_refresh, optional: true
  has_many :balance_observations, dependent: :restrict_with_error
  validates :balance, :reported_at, :fetched_at, :currency, :content_digest, presence: true

  def normalized_balance
    balance * connected_account.sign_multiplier
  end

  def stale?
    reported_at < 48.hours.ago
  end
end
