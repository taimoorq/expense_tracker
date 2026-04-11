class Subscription < ApplicationRecord
  include PlanningTemplateMetadata
  include RecurringEntryTemplate
  include TemplateAccountLinkable

  belongs_to :user
  belongs_to :linked_account, class_name: "Account", optional: true
  template_account_association :linked_account
  planning_template_metadata(
    type_key: :subscription,
    source_file: "subscription",
    param_key: :subscription,
    recurring_source: true,
    wizard_sections: %w[fixed variable manual auto other],
    permitted_attributes: [ :name, :amount, :due_day, :linked_account_id, :account, :active, :notes ]
  )

  validates :name, presence: true
  validates :amount, presence: true
  validates :due_day, inclusion: { in: 1..31 }

  scope :active_only, -> { where(active: true).order(:due_day, :name) }

  def due_date_for_month(month_on)
    Date.new(month_on.year, month_on.month, [ due_day, month_on.end_of_month.day ].min)
  end

  def matches_entry?(entry, month_on:)
    matches_entry_for_month?(entry, month_on: month_on)
  end

  def recurring_month_occurrences(month_on)
    [ due_date_for_month(month_on) ]
  end

  private

  def generated_entry_amount(month_on:, occurred_on:)
    amount
  end

  def generated_entry_section
    :fixed
  end

  def generated_entry_category
    "Subscription"
  end

  def generated_entry_notes(month_on:, occurred_on:)
    notes
  end

  def strict_matching_amount?
    true
  end
end
