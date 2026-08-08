class Category < ApplicationRecord
  enum :flow_kind, { income: "income", outflow: "outflow", transfer: "transfer" }, prefix: true
  enum :budget_group, {
    fixed: "fixed",
    variable: "variable",
    debt: "debt",
    savings: "savings",
    other: "other"
  }, prefix: true

  belongs_to :budget_workspace
  has_many :budget_items, dependent: :restrict_with_error
  has_many :planning_templates, dependent: :restrict_with_error
  has_many :financial_transactions, dependent: :restrict_with_error

  validates :name,
    presence: true,
    uniqueness: { scope: :budget_workspace_id, case_sensitive: false, conditions: -> { where(archived_at: nil) } }
  validates :display_order, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(archived_at: nil) }
end
