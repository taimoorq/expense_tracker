module ExpenseEntryProvenance
  extend ActiveSupport::Concern

  included do
    before_validation :normalize_provenance
  end

  private

  def normalize_provenance
    self.source_file = "manual" if source_file.blank?
    self.source_account = resolved_source_account
    self.account = source_account.name if source_account.present?
  end

  def resolved_source_account
    return source_account if source_account.present?

    linked_template_account = source_template_account
    return linked_template_account if linked_template_account.present?
    return nil if user.blank? || account.blank?

    user.accounts.find_by(name: account)
  end

  def source_template_account
    return nil if source_template.blank?
    return source_template.entry_account_record if source_template.respond_to?(:entry_account_record)
    return source_template.payment_account if source_template.respond_to?(:payment_account) && source_template.payment_account.present?
    return source_template.linked_account if source_template.respond_to?(:linked_account)
    return source_template.payment_account if source_template.respond_to?(:payment_account)

    nil
  end
end
