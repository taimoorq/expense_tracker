class ExpenseEntryAccountLinking
  class << self
    def relink_for(user)
      user.expense_entries.where(source_account_id: nil).where.not(account: [ nil, "" ]).find_each do |entry|
        linked_account = linked_account_for(entry)
        next if linked_account.blank?

        entry.update_columns(source_account_id: linked_account.id, updated_at: Time.current)
      end
    end

    private

    def linked_account_for(entry)
      template_account = entry.source_template&.linked_account if entry.source_template.respond_to?(:linked_account)
      return template_account if template_account.present?

      entry.user.accounts.find_by(name: entry.account)
    end
  end
end
