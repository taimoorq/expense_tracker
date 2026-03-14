class User < ApplicationRecord
  enum :access_state, {
    active: 0,
    suspended: 1
  }, default: :active, prefix: true

  has_many :accounts, dependent: :destroy
  has_many :budget_months, dependent: :destroy
  has_many :account_snapshots, through: :accounts
  has_many :expense_entries, dependent: :destroy
  has_many :pay_schedules, dependent: :destroy
  has_many :subscriptions, dependent: :destroy
  has_many :monthly_bills, dependent: :destroy
  has_many :payment_plans, dependent: :destroy
  has_many :credit_cards, dependent: :destroy

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  def active_for_authentication?
    super && access_state_active?
  end

  def inactive_message
    access_state_suspended? ? :suspended : super
  end
end
