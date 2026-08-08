module Accounts
  class LegacyMatchBridge
    def self.match(workspace:, actor_membership:, transaction:, budget_item:, amount:, idempotency_key:)
      ApplicationRecord.transaction do
        outcome = Accounts::MatchTransaction.call(
          workspace: workspace,
          actor_membership: actor_membership,
          transaction: transaction,
          budget_item: budget_item,
          amount: amount,
          idempotency_key: idempotency_key
        )
        link_legacy_records!(workspace: workspace, transaction: transaction, budget_item: budget_item)
        outcome
      end
    end

    def self.unmatch(workspace:, actor_membership:, allocation:, idempotency_key:)
      ApplicationRecord.transaction do
        transaction = allocation.financial_transaction
        budget_item = allocation.budget_item
        outcome = Accounts::UnmatchTransaction.call(
          workspace: workspace,
          actor_membership: actor_membership,
          allocation: allocation,
          idempotency_key: idempotency_key
        )
        unlink_legacy_records!(workspace: workspace, transaction: transaction, budget_item: budget_item)
        outcome
      end
    end

    def self.link_legacy_records!(workspace:, transaction:, budget_item:)
      activity = legacy_record(workspace, transaction, AccountActivity)
      entry = legacy_record(workspace, budget_item, ExpenseEntry)
      return if activity.blank? && entry.blank?
      raise MissingLegacyPair, "This match is missing its rollback-compatible source record" if activity.blank? || entry.blank?
      if activity.expense_entry_id.present? && activity.expense_entry_id != entry.id
        raise ConflictingLegacyMatch, "This imported activity is already connected to another plan entry"
      end

      activity.update!(expense_entry: entry)
    end
    private_class_method :link_legacy_records!

    def self.unlink_legacy_records!(workspace:, transaction:, budget_item:)
      activity = legacy_record(workspace, transaction, AccountActivity)
      entry = legacy_record(workspace, budget_item, ExpenseEntry)
      return if activity.blank? && entry.blank?
      raise MissingLegacyPair, "This unmatch is missing its rollback-compatible source record" if activity.blank? || entry.blank?

      activity.update!(expense_entry: nil) if activity.expense_entry_id == entry.id
    end
    private_class_method :unlink_legacy_records!

    def self.legacy_record(workspace, target, legacy_class)
      mapping = workspace.legacy_record_mappings.find_by(
        target_record_type: target.class.name,
        target_record_id: target.id,
        legacy_record_type: legacy_class.name,
        status: "mapped"
      )
      legacy_class.find_by(id: mapping&.legacy_record_id)
    end
    private_class_method :legacy_record

    class MissingLegacyPair < StandardError; end
    class ConflictingLegacyMatch < StandardError; end
  end
end
