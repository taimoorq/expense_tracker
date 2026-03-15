class User < ApplicationRecord
  enum :access_state, {
    active: 0,
    suspended: 1
  }, default: :active, prefix: true

  enum :default_landing_page, {
    overview: "overview",
    months: "months",
    planning_templates: "planning_templates",
    accounts: "accounts",
    settings: "settings"
  }, default: :overview, prefix: true

  enum :preferred_month_view, {
    timeline: "timeline",
    breakdown: "breakdown",
    calendar: "calendar",
    entries: "entries"
  }, default: :timeline, prefix: true

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
      :recoverable, :rememberable, :validatable, :lockable

  validates :default_landing_page, inclusion: { in: default_landing_pages.keys }
  validates :preferred_month_view, inclusion: { in: preferred_month_views.keys }

  def active_for_authentication?
    super && access_state_active?
  end

  def inactive_message
    access_state_suspended? ? :suspended : super
  end

  def landing_page_path
    case default_landing_page
    when "months"
      Rails.application.routes.url_helpers.budget_months_path
    when "planning_templates"
      Rails.application.routes.url_helpers.planning_templates_path
    when "accounts"
      Rails.application.routes.url_helpers.accounts_path
    when "settings"
      Rails.application.routes.url_helpers.settings_path
    else
      Rails.application.routes.url_helpers.root_path
    end
  end
end
