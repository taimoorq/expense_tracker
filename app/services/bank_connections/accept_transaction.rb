module BankConnections
  class AcceptTransaction
    def self.call(source:, membership:, digest:, entry: nil, transfer_account: nil, counterpart: nil)
      new(source: source, membership: membership, digest: digest, entry: entry, transfer_account: transfer_account, counterpart: counterpart).call
    end

    def initialize(source:, membership:, digest:, entry:, transfer_account:, counterpart:)
      @source, @membership, @digest, @entry, @transfer_account, @counterpart = source, membership, digest, entry, transfer_account, counterpart
      @workspace = source.budget_workspace
      @account = source.connected_account.account
    end

    def call
      Access.authorize!(workspace: workspace, membership: membership)
      raise ArgumentError, "This workspace must finish its ledger migration before accepting bank activity." unless workspace.target_reads_enabled? && workspace.target_writes_enabled?
      raise ArgumentError, "Map this bank account before importing activity." unless account
      raise ArgumentError, "Wait for this transaction to post before accepting it." if source.pending? || source.posted_at.nil?
      ApplicationRecord.transaction do
        workspace.lock!
        source.lock!
        raise ArgumentError, "This transaction changed. Review its latest version." unless source.content_digest == digest
        return source.financial_transaction if source.state == "accepted"
        validate_closed_months!
        validate_entry!
        validate_counterpart!
        reverse_previous!
        transaction = create_transaction!
        link_entry!(transaction) if entry
        source.update!(financial_transaction: transaction, expense_entry: entry, resolution_kind: "imported", state: "accepted")
        Audit::Recorder.call(workspace: workspace, actor_membership: membership, operation_run: nil,
          entity: transaction, action: "import", changed_fields: %i[provider_transaction_id account_postings])
        transaction
      end
    end

    private

    attr_reader :source, :membership, :digest, :entry, :workspace, :account, :transfer_account, :counterpart

    def date
      source.posted_at.in_time_zone(workspace.time_zone).to_date
    end

    def validate_closed_months!
      dates = [ date, source.financial_transaction&.effective_on, entry&.occurred_on ].compact
      if workspace.budget_periods.where(starts_on: dates.map(&:beginning_of_month), state: %w[closed closing]).exists?
        raise ArgumentError, "Reopen the affected month before importing or correcting this activity."
      end
    end

    def validate_entry!
      return unless entry
      unless entry.budget_workspace_id == workspace.id && [ entry.source_account_id, entry.destination_account_id ].include?(account.id)
        raise ArgumentError, "Choose a plan entry for this account and workspace."
      end
      direction = entry.source_account_id == account.id ? (entry.income? ? 1 : -1) : 1
      unless direction.nonzero? && direction.positive? == source.amount.positive?
        raise ArgumentError, "The transaction and plan must move money in the same direction."
      end
      raise ArgumentError, "This plan already has CSV activity. Resolve the existing match first." if entry.account_activities.exists?
    end

    def validate_counterpart!
      return unless transfer_account || counterpart || entry&.destination_account_id
      if transfer_account && (transfer_account.budget_workspace_id != workspace.id || transfer_account.id == account.id)
        raise ArgumentError, "Choose another account in this workspace for the transfer."
      end
      return unless counterpart
      counterpart.lock!
      unless counterpart.budget_workspace_id == workspace.id && counterpart.connected_account.account_id.present? &&
          counterpart.connected_account.account_id != account.id && counterpart.amount == -source.amount &&
          counterpart.currency == source.currency && !counterpart.pending? && counterpart.posted_at.present?
        raise ArgumentError, "The other transfer side must be an equal opposite posted movement in another account."
      end
      if counterpart.financial_transaction && (!counterpart.financial_transaction.flow_kind_transfer? || counterpart.financial_transaction.account_postings.count != 1)
        raise ArgumentError, "That transaction already has a complete ledger effect. Review its existing match."
      end
      peer_date = counterpart.posted_at.in_time_zone(workspace.time_zone).to_date
      if workspace.budget_periods.where(starts_on: peer_date.beginning_of_month, state: %w[closed closing]).exists?
        raise ArgumentError, "Reopen the transfer's other month before pairing it."
      end
    end

    def reverse_previous!
      previous = source.financial_transaction
      return unless previous
      raise ArgumentError, "Detach the bank evidence before reviewing this correction; the existing transaction is retained." if source.resolution_kind == "existing"
      raise ArgumentError, "Unmatch this transaction before accepting a bank correction." if previous.budget_allocations.exists? || previous.payment_settlements.exists? || previous.provider_transactions.where.not(id: source.id).exists?
      previous.update!(state: "reversed")
    end

    def create_transaction!
      is_transfer = transfer_account || counterpart || entry&.destination_account_id
      transaction = counterpart&.financial_transaction
      transaction ||= workspace.financial_transactions.create!(effective_on: date, transacted_at: source.transacted_at, posted_at: source.posted_at,
        timing_time_zone: workspace.time_zone, posted_on: date, description: source.description, gross_amount: source.amount.abs,
        currency_code: source.currency, state: "posted", origin_kind: "institution_import", reviewed_at: Time.current,
        flow_kind: is_transfer ? "transfer" : source.amount.positive? ? "income" : "outflow",
        provider_transaction_id: "simplefin:#{source.id}:#{digest}:#{SecureRandom.uuid}")
      add_posting!(transaction, source)
      if counterpart && counterpart.financial_transaction_id.nil?
        add_posting!(transaction, counterpart)
        counterpart.update!(financial_transaction: transaction, state: "accepted", expense_entry: entry)
      end
      transaction
    end

    def add_posting!(transaction, provider)
      transaction.account_postings.create!(budget_workspace: workspace, account: provider.connected_account.account,
        amount: provider.amount, currency_code: provider.currency, effective_at: provider.posted_at,
        role: transaction.flow_kind_transfer? ? (provider.amount.negative? ? "source" : "destination") : "primary",
        sequence_number: transaction.account_postings.maximum(:sequence_number).to_i + (transaction.account_postings.exists? ? 1 : 0))
    end

    def link_entry!(transaction)
      entry.lock!
      item_mapping = workspace.legacy_record_mappings.status_mapped.find_by(legacy_record_type: "ExpenseEntry", legacy_record_id: entry.id, target_record_type: "BudgetItem")
      raise ArgumentError, "The plan entry has not been synchronized with this workspace." unless item_mapping
      item = workspace.budget_items.find(item_mapping.target_record_id)
      Accounts::OpenPeriodGuard.call(workspace: workspace, dates: [ item.budget_period.starts_on ])
      if item.financial_transactions.state_posted.where(origin_kind: "manual").where("financial_transactions.idempotency_key LIKE ?", "operation:%").exists?
        raise ArgumentError, "This plan already has recorded manual activity. Attach the bank evidence to that existing transaction."
      end
      synthetic_mapping = workspace.legacy_record_mappings.status_mapped.find_by(legacy_record_type: "ExpenseEntry", legacy_record_id: entry.id, target_record_type: "FinancialTransaction")
      synthetic = workspace.financial_transactions.find_by(id: synthetic_mapping&.target_record_id)
      if synthetic && synthetic != transaction && synthetic.origin_kind_manual?
        synthetic.update!(state: "reversed")
      end
      allocation = transaction.budget_allocations.find_or_initialize_by(budget_item: item)
      allocation.assign_attributes(budget_workspace: workspace, amount: transaction.gross_amount, currency_code: source.currency,
        match_kind: "manual", matched_by_membership: membership, matched_at: Time.current)
      allocation.save!
      commitment = entry.payment_commitments.find_by(state: "reserved")
      if commitment && source.amount.negative? && commitment.account_id == account.id
        settlement = [ commitment.outstanding_amount, source.amount.abs ].min
        if settlement.positive?
          commitment.payment_settlements.find_or_create_by!(financial_transaction: transaction) do |record|
            record.assign_attributes(budget_workspace: workspace, amount: settlement)
          end
        end
        commitment.update!(state: "settled") if commitment.outstanding_amount.zero?
      end
      # Keep the compatibility entry in sync without invoking its synthetic
      # posting writer. Future edits see the provider link and preserve evidence.
      Accounts::PlanActualWriter.call(entry: entry, item: item)
    end
  end
end
