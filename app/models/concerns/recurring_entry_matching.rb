module RecurringEntryMatching
  extend ActiveSupport::Concern

  def matches_entry_for_month?(entry, month_on:)
    return false if entry.blank? || entry.occurred_on.blank?
    return false unless comparable_match_text(entry.payee) == comparable_match_text(name)
    return false unless recurring_month_occurrences(month_on).include?(entry.occurred_on)
    return false unless matching_entry_origin?(entry)
    return false unless matching_account?(entry)
    return false unless matching_amount?(entry, month_on: month_on)

    true
  end

  def represents_entry_for_month?(entry, month_on:)
    return false if entry.blank? || entry.occurred_on.blank?
    return false unless month_on.to_date.all_month.cover?(entry.occurred_on.to_date)
    return false unless comparable_match_text(entry.payee) == comparable_match_text(name)
    return false unless matching_entry_origin?(entry)
    return false unless matching_account?(entry)
    return false unless matching_amount?(entry, month_on: month_on)

    true
  end

  private

  def matching_entry_sections
    [ generated_entry_section.to_s ]
  end

  def matching_entry_source_files
    [ recurring_source_file ].compact
  end

  def matching_entry_origin?(entry)
    matching_entry_template_link?(entry) ||
      matching_entry_source_files.include?(entry.source_file) ||
      matching_entry_sections.include?(entry.section) ||
      comparable_match_text(entry.category) == comparable_match_text(generated_entry_category)
  end

  def matching_entry_template_link?(entry)
    return false unless id.present?
    return false unless entry.respond_to?(:source_template_type) && entry.respond_to?(:source_template_id)

    entry.source_template_type == model_name.name && entry.source_template_id == id
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
