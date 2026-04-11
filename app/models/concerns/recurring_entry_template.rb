module RecurringEntryTemplate
  extend ActiveSupport::Concern

  def recurring_source_file
    self.class.template_source_file
  end

  def matches_entry_for_month?(entry, month_on:)
    return false if entry.blank? || entry.occurred_on.blank?
    return false unless comparable_match_text(entry.payee) == comparable_match_text(name)
    return false unless recurring_month_occurrences(month_on).include?(entry.occurred_on)
    return false unless matching_entry_source_files.include?(entry.source_file) || matching_entry_sections.include?(entry.section)
    return false unless matching_account?(entry)
    return false unless matching_amount?(entry, month_on: month_on)

    true
  end

  def recurring_month_occurrences(_month_on)
    raise NotImplementedError, "#{self.class.name} must implement #recurring_month_occurrences"
  end

  def generated_entry_exists?(budget_month, occurred_on)
    budget_month.expense_entries.any? do |entry|
      matches_entry_for_month?(entry, month_on: budget_month.month_on) && entry.occurred_on == occurred_on
    end
  end

  def build_generated_entry_attributes(month_on:, occurred_on:)
    {
      occurred_on: occurred_on,
      section: generated_entry_section,
      category: generated_entry_category,
      payee: name,
      planned_amount: generated_entry_amount(month_on: month_on, occurred_on: occurred_on),
      actual_amount: nil,
      account: account_name,
      status: :planned,
      need_or_want: "Need",
      notes: generated_entry_notes(month_on: month_on, occurred_on: occurred_on),
      source_file: recurring_source_file,
      source_template: self
    }
  end

  private

  def generated_entry_amount(month_on:, occurred_on:)
    raise NotImplementedError, "#{self.class.name} must implement #generated_entry_amount"
  end

  def generated_entry_section
    raise NotImplementedError, "#{self.class.name} must implement #generated_entry_section"
  end

  def generated_entry_category
    raise NotImplementedError, "#{self.class.name} must implement #generated_entry_category"
  end

  def generated_entry_notes(month_on:, occurred_on:)
    nil
  end

  def matching_entry_sections
    [ generated_entry_section.to_s ]
  end

  def matching_entry_source_files
    [ recurring_source_file ].compact
  end

  def strict_matching_amount?
    false
  end

  def comparable_match_text(value)
    value.to_s.strip.downcase
  end

  def matching_account?(entry)
    expected_account = account_name
    return true if expected_account.blank?

    comparable_match_text(entry.account_name) == comparable_match_text(expected_account)
  end

  def matching_amount?(entry, month_on:)
    return true unless strict_matching_amount?

    expected_amount = generated_entry_amount(month_on: month_on, occurred_on: entry.occurred_on)
    return true if expected_amount.blank?

    entry.effective_amount.to_d == expected_amount.to_d
  end
end
