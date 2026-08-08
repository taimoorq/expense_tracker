class ImportProfile < ApplicationRecord
  enum :amount_strategy, {
    charges_are_negative: "charges_are_negative",
    charges_are_positive: "charges_are_positive",
    type_column: "type_column"
  }, prefix: true

  belongs_to :budget_workspace
  belongs_to :account, optional: true
  has_many :import_batches, dependent: :restrict_with_error

  validates :name, :parser_name, :parser_version, :fingerprint_version, presence: true
  validates :name, uniqueness: { scope: :budget_workspace_id, case_sensitive: false }
  validates :header_row_number, numericality: { only_integer: true, greater_than: 0 }
end
