module RecurringEntryTemplate
  extend ActiveSupport::Concern
  include RecurringEntryMatching

  GENERATED_ENTRY_KEY_VERSION = "recurring:v1".freeze

  def recurring_source_file
    template_source_file
  end

  def recurring_month_occurrences(_month_on)
    raise NotImplementedError, "#{model_name.name} must implement #recurring_month_occurrences"
  end

  def generated_entry_exists?(budget_month, occurred_on)
    Recurring::MonthTemplateCoverage
      .new(template: self, budget_month: budget_month, entries: budget_month.expense_entries.to_a)
      .matched_occurrence?(occurred_on)
  end

  def generated_entry_key(month_on:, occurred_on:)
    return nil if id.blank? || month_on.blank? || occurred_on.blank?

    [
      GENERATED_ENTRY_KEY_VERSION,
      model_name.name,
      id,
      month_on.to_date.beginning_of_month.iso8601,
      occurred_on.to_date.iso8601
    ].join(":")
  end

  def build_generated_entry_attributes(month_on:, occurred_on:)
    {
      generated_entry_key: generated_entry_key(month_on: month_on, occurred_on: occurred_on),
      occurred_on: occurred_on,
      section: generated_entry_section,
      category: generated_entry_category,
      payee: name,
      planned_amount: generated_entry_amount(month_on: month_on, occurred_on: occurred_on),
      actual_amount: nil, account: account_name,
      status: :planned,
      need_or_want: "Need"
    }.merge(generated_entry_metadata(month_on: month_on, occurred_on: occurred_on))
  end

  private

  def generated_entry_amount(month_on:, occurred_on:)
    raise NotImplementedError, "#{model_name.name} must implement #generated_entry_amount"
  end

  def generated_entry_section
    raise NotImplementedError, "#{model_name.name} must implement #generated_entry_section"
  end

  def generated_entry_category
    raise NotImplementedError, "#{model_name.name} must implement #generated_entry_category"
  end

  def generated_entry_notes(month_on:, occurred_on:)
    nil
  end

  def generated_entry_metadata(month_on:, occurred_on:)
    {
      notes: generated_entry_notes(month_on: month_on, occurred_on: occurred_on),
      source_file: recurring_source_file,
      source_template: self
    }
  end
end
