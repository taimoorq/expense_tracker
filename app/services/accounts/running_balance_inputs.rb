module Accounts
  # Both workspace read modes supply signed movements and their linked table rows.
  class RunningBalanceInputs
    def initialize(account:, through_on:)
      @account = account
      @through_on = through_on
    end

    def events
      account.budget_workspace&.target_reads_enabled? ? target_events : legacy_events
    end

    private

    attr_reader :account, :through_on

    def event(key:, date:, kind:, amount:, entries: [], created_at: nil, timestamp: nil)
      linked = entries.compact.select { |entry| entry.occurred_on.present? }
      timestamp ||= linked.filter_map(&:occurred_at).min
      instant = TransactionTiming.at(date: date, incoming: kind != :report && amount.to_d.positive?, timestamp: timestamp, workspace: account.budget_workspace)
      ordered_at = linked.map(&:created_at).compact.min || created_at
      EntryRunningBalances::Event.new(key: key, date: date, kind: kind, amount: amount.to_d,
        entries: linked, order: [ instant&.to_r || 0, kind == :report ? 1 : 0, ordered_at&.to_r || 0, linked.map(&:id).min.to_s ])
    end

    def entries
      @entries ||= account.user.expense_entries
        .where("source_account_id = :id OR destination_account_id = :id", id: account.id)
        .where(occurred_on: ..through_on).to_a.index_by(&:id)
    end

    def signed_amount(record, amount)
      source_id = record.is_a?(BudgetItem) ? record.intended_source_account_id : record.source_account_id
      destination_id = record.is_a?(BudgetItem) ? record.intended_destination_account_id : record.destination_account_id
      income = record.is_a?(BudgetItem) ? record.flow_kind_income? : record.income?
      delta = source_id == account.id ? (income ? amount : -amount) : 0.to_d
      delta += amount if destination_id == account.id
      delta
    end

    def legacy_events
      reports = account.account_snapshots.where(recorded_on: ..through_on).map do |snapshot|
        event(key: "report-#{snapshot.updated_at.iso8601(6)}-0-#{snapshot.id}", date: snapshot.recorded_on,
          kind: :report, amount: snapshot.balance)
      end
      imports = account.account_activity_imports.to_a
      reports += imports.select(&:institution_balance?).filter_map do |import|
        date = BalanceSource.institution_balance_source_date(import)
        next if date > through_on

        event(key: "report-#{import.created_at.iso8601(6)}-1-#{import.id}", date: date,
          kind: :report, amount: import.institution_balance)
      end
      activity = account.account_activities.where(transaction_on: ..through_on).to_a
      matched_ids = activity.filter_map(&:expense_entry_id).to_set
      movements = activity.map do |row|
        event(key: "activity-#{row.id}", date: row.transaction_on, kind: :actual, amount: row.account_delta,
          entries: [ entries[row.expense_entry_id] ], created_at: row.created_at, timestamp: row.transacted_at)
      end
      movements += entries.values.filter_map do |entry|
        next if matched_ids.include?(entry.id)
        # Imported activity is authoritative inside its coverage window. Unmatched
        # paid plans there cannot safely be assigned a separate balance/debit.
        next if entry.paid? && imports.any? { |import| import.started_on && import.ended_on && entry.occurred_on.between?(import.started_on, import.ended_on) }
        next if entry.paid? && entry.actual_amount.nil?

        amount = entry.skipped? ? 0.to_d : (entry.paid? ? entry.actual_amount.to_d : entry.planned_amount.to_d)
        event(key: "entry-#{entry.id}", date: entry.occurred_on, kind: entry.planned? ? :planned : :actual,
          amount: signed_amount(entry, amount), entries: [ entry ])
      end
      reports + movements
    end

    def target_events
      workspace = account.budget_workspace
      observation_scope = account.balance_observations.trusted.where(effective_through_at: ..TransactionTiming.at(date: through_on, incoming: false, workspace: workspace))
      observation_scope = observation_scope.where.not(source_kind: "bank_sync") unless account.connected_account&.use_bank_balance?
      observations = observation_scope.to_a
      first_bank = observations.select(&:source_kind_bank_sync?).map(&:effective_through_at).min
      observations.select! { |observation| observation.source_kind_bank_sync? || observation.effective_through_at < first_bank } if first_bank
      latest_bank = observations.select(&:source_kind_bank_sync?).max_by(&:effective_through_at)
      commitments = account.payment_commitments.where(state: "reserved", initiated_on: ..through_on).includes(:expense_entry, :included_provider_balance, :payment_settlements).to_a
      postings = account.account_postings.joins(:financial_transaction).includes(:financial_transaction)
        .where(financial_transactions: { state: "posted" })
        .where("financial_transactions.effective_on <= :date OR account_postings.effective_at <= :instant", date: through_on, instant: TransactionTiming.at(date: through_on, incoming: false, workspace: workspace)).to_a
        .select { |posting| (posting.effective_at&.in_time_zone(workspace.time_zone)&.to_date || posting.financial_transaction.effective_on) <= through_on }
      reports = observations.map do |observation|
        priority = observation.source_kind_institution_file? ? 1 : 0
        reservation_delta = if observation.source_kind_bank_sync?
          policy = BankBalancePolicy.new(account: account, observation: observation)
          commitments.sum do |payment|
            instant = TransactionTiming.at(date: payment.initiated_on, incoming: false, timestamp: payment.initiated_at, workspace: workspace)
            instant <= observation.effective_through_at && policy.payment_disposition(payment) == "outside" ? payment.outstanding_amount : 0.to_d
          end
        else
          0.to_d
        end
        correction = if observation.source_kind_bank_sync?
          postings.sum do |posting|
            transaction = posting.financial_transaction
            instant = TransactionTiming.at(date: transaction.effective_on, incoming: posting.amount.positive?, timestamp: posting.effective_at || transaction.transacted_at, workspace: workspace)
            instant <= observation.effective_through_at && policy.disposition(posting) == "outside" ? posting.amount : 0.to_d
          end
        else
          0.to_d
        end
        event(key: "report-#{observation.created_at.iso8601(6)}-#{priority}-#{observation.id}",
          date: observation.effective_through_at.in_time_zone(workspace.time_zone).to_date, kind: :report, amount: observation.balance - reservation_delta + correction, timestamp: observation.effective_through_at)
      end
      items = workspace.budget_items.where(state: %w[open skipped])
        .where("intended_source_account_id = :id OR intended_destination_account_id = :id", id: account.id)
        .where(scheduled_on: ..through_on).to_a
      item_entries = mapped_entries(workspace, "BudgetItem", items.map(&:id))
      transaction_entries = mapped_entries(workspace, "FinancialTransaction", postings.map(&:financial_transaction_id))
      allocations = workspace.budget_allocations.joins(:financial_transaction)
        .where(budget_item_id: items.map(&:id), financial_transactions: { state: "posted" }).to_a
      allocated = allocations.group_by(&:budget_item_id).transform_values { |rows| rows.sum(&:amount) }
      linked_entries = allocations.group_by(&:financial_transaction_id).transform_values do |rows|
        rows.filter_map { |allocation| item_entries[allocation.budget_item_id] }
      end
      movements = postings.group_by(&:financial_transaction_id).map do |transaction_id, values|
        transaction = values.first.financial_transaction
        linked = [ transaction_entries[transaction_id], *linked_entries.fetch(transaction_id, []) ].compact.uniq
        posting_time = values.first.effective_at || transaction.transacted_at
        instant = TransactionTiming.at(date: transaction.effective_on, incoming: values.sum(&:amount).positive?, timestamp: posting_time, workspace: workspace)
        preceding = observations.select { |observation| observation.effective_through_at < instant }.max_by(&:effective_through_at)
        amount = values.sum { |posting| posting.amount.to_d }
        if preceding&.source_kind_bank_sync? && values.all? { |posting| BankBalancePolicy.new(account: account, observation: preceding).disposition(posting) == "included" }
          amount = 0.to_d
        end
        event(key: "transaction-#{transaction_id}", date: posting_time&.in_time_zone(workspace.time_zone)&.to_date || transaction.effective_on, kind: :actual,
          amount: amount, entries: linked, created_at: transaction.created_at, timestamp: posting_time)
      end
      movements += items.filter_map do |item|
        entry = item_entries[item.id]
        # Compatibility rows marked paid are complete even when actual != plan.
        next if entry&.paid? && entry.actual_amount != 0 && commitments.none? { |payment| payment.expense_entry_id == entry.id }

        reserved_amount = commitments.select { |payment| payment.expense_entry_id == entry&.id }.sum(&:outstanding_amount)
        remaining = [ item.planned_amount - allocated.fetch(item.id, 0.to_d) - reserved_amount, 0.to_d ].max
        remaining = 0.to_d if item.state_skipped? || (entry&.paid? && reserved_amount.zero?)
        next if remaining.zero? && allocated.fetch(item.id, 0).positive?

        amount = signed_amount(item, remaining)
        instant = TransactionTiming.at(date: item.scheduled_on, incoming: amount.positive?, timestamp: item.scheduled_at, workspace: workspace)
        date, timestamp = item.scheduled_on, item.scheduled_at
        if latest_bank && instant && instant <= latest_bank.effective_through_at && remaining.positive?
          timestamp = latest_bank.effective_through_at + Rational(1, 1_000_000)
          date = timestamp.in_time_zone(workspace.time_zone).to_date
        end
        event(key: "item-#{item.id}", date: date, kind: :planned,
          amount: amount, entries: [ entry ], created_at: item.created_at, timestamp: timestamp)
      end
      movements += commitments.filter_map do |payment|
        instant = TransactionTiming.at(date: payment.initiated_on, incoming: false, timestamp: payment.initiated_at, workspace: workspace)
        preceding = observations.select { |observation| observation.effective_through_at < instant }.max_by(&:effective_through_at)
        included = preceding&.source_kind_bank_sync? && BankBalancePolicy.new(account: account, observation: preceding).payment_disposition(payment) == "included"
        event(key: "reservation-#{payment.id}", date: payment.initiated_on, kind: :reservation,
          amount: included ? 0.to_d : -payment.outstanding_amount, entries: [ payment.expense_entry ], created_at: payment.created_at, timestamp: payment.initiated_at)
      end
      reports + movements
    end

    def mapped_entries(workspace, target_type, ids)
      workspace.legacy_record_mappings.status_mapped.where(legacy_record_type: "ExpenseEntry", target_record_type: target_type, target_record_id: ids)
        .pluck(:target_record_id, :legacy_record_id).to_h.transform_values { |id| entries[id] }
    end
  end
end
