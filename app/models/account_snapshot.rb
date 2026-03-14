class AccountSnapshot < ApplicationRecord
  belongs_to :account

  delegate :user, to: :account

  validates :recorded_on, presence: true, uniqueness: { scope: :account_id }
  validates :balance, presence: true
end
