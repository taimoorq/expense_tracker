module Budgeting
  class MonthAccountFlowSummary
    def self.cached_payload(budget_month:, expense_entries: nil)
      expense_entries ||= fresh_expense_entries(budget_month)

      Rails.cache.fetch(cache_key_for(budget_month: budget_month, expense_entries: expense_entries), expires_in: 12.hours) do
        loaded_entries = preload_payload_associations(expense_entries)
        new(budget_month: budget_month, expense_entries: loaded_entries).payload
      end
    end

    def initialize(budget_month:, expense_entries: nil)
      @budget_month = budget_month
      @expense_entries = expense_entries || self.class.send(:fresh_expense_entries, budget_month)
      @entries = @expense_entries.to_a
    end

    def payload
      Accounts::AccountFlowSummary.new(expense_entries: entries).payload
    end

    private

    attr_reader :budget_month, :expense_entries, :entries

    def self.fresh_expense_entries(budget_month)
      budget_month.expense_entries.reset
    end
    private_class_method :fresh_expense_entries

    def self.preload_payload_associations(expense_entries)
      entries = expense_entries.to_a
      ActiveRecord::Associations::Preloader.new(records: entries, associations: :source_template).call

      card_payment_entries, account_activity_entries = entries.partition do |entry|
        entry.source_template.is_a?(CreditCard) || entry.source_file == CreditCard.template_source_file
      end

      entries_with_source_accounts = account_activity_entries.select { |entry| entry.source_account_id.present? }
      if entries_with_source_accounts.any?
        ActiveRecord::Associations::Preloader.new(records: entries_with_source_accounts, associations: :source_account).call
      end

      entries_with_destinations = card_payment_entries.select { |entry| entry.destination_account_id.present? }
      if entries_with_destinations.any?
        ActiveRecord::Associations::Preloader.new(records: entries_with_destinations, associations: :destination_account).call
      end

      legacy_card_templates = card_payment_entries.filter_map do |entry|
        entry.source_template if entry.destination_account_id.blank? && entry.source_template.is_a?(CreditCard)
      end
      if legacy_card_templates.any?
        ActiveRecord::Associations::Preloader.new(records: legacy_card_templates, associations: :linked_account).call
      end

      entries
    end
    private_class_method :preload_payload_associations

    def self.cache_key_for(budget_month:, expense_entries:)
      relation_updated_at =
        if expense_entries.respond_to?(:maximum)
          expense_entries.maximum(:updated_at)
        else
          Array(expense_entries).filter_map(&:updated_at).max
        end

      relation_count =
        if expense_entries.respond_to?(:count)
          expense_entries.count
        else
          Array(expense_entries).size
        end

      [
        "budget_months",
        budget_month.id,
        "account_flow",
        budget_month.cache_key_with_version,
        relation_count,
        relation_updated_at&.utc&.iso8601(6)
      ]
    end
  end
end
