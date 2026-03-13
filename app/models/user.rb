class User < ApplicationRecord
  has_many :budget_months, dependent: :destroy
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
end
