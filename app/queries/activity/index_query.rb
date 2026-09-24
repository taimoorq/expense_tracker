module Activity
  class IndexQuery
    VIEWS = %w[review bank pending ignored payments all unmatched imports].freeze
    LIMIT = 100

    Row = Data.define(
      :id, :occurred_on, :ordering_at, :description, :account, :amount, :direction, :source,
      :state, :matched, :detail_path, :transaction_id, :allocation_id, :available_amount,
      :migration_discrepancy_id, :provider_id, :provider_resolution_kind
    )
    MatchingOption = Data.define(:id, :label, :flow_kind, :remaining_amount)
    Result = Data.define(
      :view, :rows, :counts, :accounts, :imports, :limited, :calculation_version,
      :target_mode, :matching_options, :account_id, :starts_on, :ends_on, :direction,
      :transaction_id, :actions_available, :page, :source
    )

    def self.call(user:, view: nil, account_id: nil, starts_on: nil, ends_on: nil, direction: nil, transaction_id: nil, page: nil, source: nil)
      new(
        user: user,
        view: view,
        account_id: account_id,
        starts_on: starts_on,
        ends_on: ends_on,
        direction: direction,
        transaction_id: transaction_id, page: page, source: source
      ).call
    end

    def initialize(user:, view:, account_id:, starts_on:, ends_on:, direction:, transaction_id:, page:, source:)
      @source = source.to_s.in?(%w[manual csv simplefin]) ? source.to_s : nil
      @page = [ page.to_i, 1 ].max
      @user = user
      @view = VIEWS.include?(view.to_s) ? view.to_s : "review"
      @account_id = account_id.presence
      @starts_on = parse_date(starts_on)
      @ends_on = parse_date(ends_on)
      @direction = direction.to_s.in?(%w[incoming outgoing]) ? direction.to_s : nil
      @transaction_id = transaction_id.presence
    end

    def call
      selected_rows = filtered_rows
      Result.new(
        view: view, page: page, source: source,
        rows: selected_rows.first(LIMIT),
        counts: counts,
        accounts: user.accounts.active_first.to_a,
        imports: view == "imports" ? import_scope.includes(:account).recent_first.limit(25).to_a : [],
        limited: selected_rows.size > LIMIT,
        calculation_version: target_reads? ? "target-v1" : "legacy-compatible-v1",
        target_mode: target_reads?,
        matching_options: matching_options,
        account_id: account_id,
        starts_on: starts_on,
        ends_on: ends_on,
        direction: direction,
        transaction_id: transaction_id,
        actions_available: target_reads? || selected_rows.any? { |row| row.migration_discrepancy_id.present? }
      )
    end

    private

    attr_reader :account_id, :direction, :ends_on, :starts_on, :transaction_id, :user, :view, :page, :source

    def filtered_rows
      view.in?(%w[imports bank pending ignored payments]) ? [] : all_rows
    end

    def counts
      return @counts if @counts
      @counts = (target_reads? ? target_counts : legacy_counts).merge(
        "bank" => provider_counts.sum { |(state, pending), count| state.in?(%w[review changed]) && !pending ? count : 0 },
        "ignored" => provider_counts.sum { |(state, _), count| state == "ignored" ? count : 0 },
        "pending" => provider_counts.sum { |(state, pending), count| state.in?(%w[review changed]) && pending ? count : 0 },
        "payments" => payment_scope&.count || 0
      )
      @counts["review"] += @counts["bank"] unless source.in?(%w[manual csv])
      @counts
    end

    def all_rows
      @all_rows ||= (target_reads? ? target_rows : legacy_rows).sort_by do |row|
        [ row.occurred_on || Date.new(1970, 1, 1), row.ordering_at&.to_r || 0, row.id ]
      end.reverse
    end

    def payment_scope
      return unless workspace

      scope = workspace.payment_commitments.where(state: "reserved")
      scope = scope.where(account_id: account_id) if account_id
      scope = scope.where(initiated_on: starts_on..) if starts_on
      scope = scope.where(initiated_on: ..ends_on) if ends_on
      scope
    end

    def target_rows
      workspace.financial_transactions.where(id: target_scope_for_view.select(:id))
        .includes(:budget_allocations, :provider_transactions, account_postings: :account)
        .order(Arel.sql(target_order))
        .offset((page - 1) * LIMIT).limit(LIMIT + 1)
        .map do |transaction|
          posting = if account_id.present?
            transaction.account_postings.find { |candidate| candidate.account_id.to_s == account_id.to_s }
          else
            transaction.account_postings.min_by(&:sequence_number)
          end
          account = posting&.account
          effective_date = account_id.present? ? posting&.effective_at&.in_time_zone(workspace.time_zone)&.to_date || transaction.effective_on : transaction.effective_on
          ordering_time = account_id.present? ? posting&.effective_at || transaction.transacted_at : transaction.transacted_at
          matched = transaction.budget_allocations.any?
          allocation = transaction.budget_allocations.min_by { |candidate| [ candidate.matched_at, candidate.id ] }
          available_amount = [ transaction.gross_amount - transaction.budget_allocations.sum(&:amount), 0 ].max
          needs_review = transaction.state_pending? ||
            (transaction.state_posted? && transaction.origin_kind_institution_import? && !matched && transaction.reviewed_at.nil?)
          Row.new(
            id: transaction.id,
            occurred_on: effective_date,
            ordering_at: Accounts::TransactionTiming.at(date: effective_date, incoming: posting&.amount.to_d.positive?, timestamp: ordering_time, workspace: workspace),
            description: transaction.description,
            account: account,
            amount: account_id.present? ? posting&.amount.to_d.abs : transaction.gross_amount,
            direction: account_id.present? && !transaction.flow_kind_transfer? ? (posting&.amount.to_d.positive? ? "income" : "outflow") : transaction.flow_kind,
            source: Activity::SourceLabel.call(transaction),
            state: needs_review ? "needs_review" : transaction.state == "posted" ? "reviewed" : transaction.state,
            matched: matched,
            detail_path: account && Rails.application.routes.url_helpers.account_path(account, view: "activity"),
            transaction_id: transaction.id,
            allocation_id: allocation&.id,
            available_amount: available_amount,
            migration_discrepancy_id: nil, provider_id: transaction.provider_transactions.first&.id, provider_resolution_kind: transaction.provider_transactions.first&.resolution_kind
          )
        end
    end

    def legacy_rows
      activities = legacy_activity_scope.includes(:account).recent_first.limit(page * LIMIT + 1).to_a
      imported = activities.map do |activity|
        matched = activity.expense_entry_id.present?
        Row.new(
          id: activity.id,
          occurred_on: activity.transaction_on,
          ordering_at: Accounts::TransactionTiming.at(date: activity.transaction_on, incoming: activity.account_delta.positive?, timestamp: activity.transacted_at, workspace: workspace),
          description: activity.description,
          account: activity.account,
          amount: activity.amount,
          direction: activity.account_delta.positive? ? "income" : "outflow",
          source: "Imported",
          state: matched ? "reviewed" : "needs_review",
          matched: matched,
          detail_path: Rails.application.routes.url_helpers.account_path(activity.account, view: "activity"),
          transaction_id: nil,
          allocation_id: nil,
          available_amount: nil,
          migration_discrepancy_id: nil, provider_id: nil, provider_resolution_kind: nil
        )
      end
      manual = legacy_manual_scope
        .includes(:source_account, :destination_account)
        .order(Arel.sql(Accounts::TransactionTiming.sql(table: "expense_entries", date: "occurred_on", timestamp: "occurred_at", incoming: "expense_entries.section = 0", descending: true)))
        .limit(page * LIMIT + 1)
        .map do |entry|
          account = entry.source_account || entry.destination_account
          needs_review = entry.actual_amount.blank? || account.blank?
          Row.new(
            id: entry.id,
            occurred_on: entry.occurred_on,
            ordering_at: Accounts::TransactionTiming.at(date: entry.occurred_on, incoming: entry.income?, timestamp: entry.occurred_at, workspace: workspace),
            description: entry.payee.presence || entry.category.presence || "Manual transaction",
            account: account,
            amount: entry.effective_amount,
            direction: Platform::TargetTranslation::ExpenseEntry.flow_kind(entry),
            source: "Manual",
            state: needs_review ? "needs_review" : "reviewed",
            matched: true,
            detail_path: entry.budget_month && Rails.application.routes.url_helpers.budget_month_tab_path(entry.budget_month, "entries", anchor: "entry-#{entry.id}"),
            transaction_id: nil,
            allocation_id: nil,
            available_amount: nil,
            migration_discrepancy_id: missing_account_discrepancies[entry.id]&.id, provider_id: nil, provider_resolution_kind: nil
          )
        end
      (imported + manual).sort_by { |row| [ row.occurred_on || Date.new(1970, 1, 1), row.ordering_at&.to_r || 0, row.id ] }.reverse.drop((page - 1) * LIMIT)
    end

    def target_scope_for_view
      case view
      when "review" then target_review_scope
      when "unmatched" then target_unmatched_scope
      else target_base_scope
      end
    end

    def target_posting_sql(field)
      quoted_account = ApplicationRecord.connection.quote(account_id)
      "(SELECT #{field} FROM account_postings timing_postings WHERE timing_postings.financial_transaction_id = financial_transactions.id AND timing_postings.account_id = #{quoted_account} ORDER BY sequence_number LIMIT 1)"
    end

    def target_date_sql
      return "financial_transactions.effective_on" if account_id.blank?
      zone = ApplicationRecord.connection.quote(workspace.time_zone)
      "COALESCE((#{target_posting_sql('effective_at')} AT TIME ZONE 'UTC' AT TIME ZONE #{zone})::date, financial_transactions.effective_on)"
    end

    def target_order
      incoming = account_id.present? ? "#{target_posting_sql('amount')} > 0" : "financial_transactions.flow_kind = 'income'"
      timestamp = account_id.present? ? "COALESCE(#{target_posting_sql('effective_at')}, financial_transactions.transacted_at)" : nil
      Accounts::TransactionTiming.sql(table: "financial_transactions", date: "effective_on", timestamp: "transacted_at", incoming: incoming,
        descending: true, date_expression: target_date_sql, timestamp_expression: timestamp)
    end

    def target_base_scope
      scope = workspace.financial_transactions
      scope = scope.where(origin_kind: "manual") if source == "manual"
      scope = scope.where.not(import_row_id: nil) if source == "csv"
      scope = scope.where(id: workspace.provider_transactions.where.not(financial_transaction_id: nil).select(:financial_transaction_id)) if source == "simplefin"
      scope = scope.where(id: transaction_id) if transaction_id.present?
      scope = scope.where(Arel.sql(target_date_sql).gteq(starts_on)) if starts_on
      scope = scope.where(Arel.sql(target_date_sql).lteq(ends_on)) if ends_on
      return scope if account_id.blank?

      scope = scope.joins(:account_postings).where(account_postings: { account_id: account_id })
      scope = scope.where("account_postings.amount > 0") if direction == "incoming"
      scope = scope.where("account_postings.amount < 0") if direction == "outgoing"
      scope.distinct
    end

    def target_review_scope
      target_base_scope.where(<<~SQL.squish)
        financial_transactions.state = 'pending'
        OR (
          financial_transactions.state = 'posted'
          AND financial_transactions.origin_kind = 'institution_import'
          AND financial_transactions.reviewed_at IS NULL
          AND NOT EXISTS (
            SELECT 1 FROM budget_allocations
            WHERE budget_allocations.financial_transaction_id = financial_transactions.id
          )
        )
      SQL
    end

    def target_unmatched_scope
      target_base_scope
        .where(state: "posted")
        .where.missing(:budget_allocations)
    end

    def target_counts
      {
        "review" => exact_count(target_review_scope),
        "all" => exact_count(target_base_scope),
        "unmatched" => exact_count(target_unmatched_scope),
        "imports" => import_scope.count
      }
    end

    def exact_count(scope)
      scope.unscope(:order).distinct.count(:id)
    end

    def legacy_activity_scope(filter_view: true)
      return user.account_activities.none if source.in?(%w[manual simplefin])
      scope = user.account_activities
      scope = scope.where(account_id: account_id) if account_id.present?
      scope = scope.where(transaction_on: starts_on..) if starts_on
      scope = scope.where(transaction_on: ..ends_on) if ends_on
      scope = scope.where("account_delta > 0") if direction == "incoming"
      scope = scope.where("account_delta < 0") if direction == "outgoing"
      return scope unless filter_view
      case view
      when "review", "unmatched" then scope.where(expense_entry_id: nil)
      else scope
      end
    end

    def legacy_manual_scope(filter_view: true)
      return user.expense_entries.none if source.in?(%w[csv simplefin])
      scope = user.expense_entries
        .paid
        .left_joins(:account_activities)
        .where(account_activities: { id: nil })
      scope = scope.where(occurred_on: starts_on..) if starts_on
      scope = scope.where(occurred_on: ..ends_on) if ends_on
      if account_id.present?
        scope = scope.where("expense_entries.source_account_id = :id OR expense_entries.destination_account_id = :id", id: account_id)
      end
      return scope unless filter_view
      return scope.where("expense_entries.actual_amount IS NULL OR (expense_entries.source_account_id IS NULL AND expense_entries.destination_account_id IS NULL)") if view == "review"
      return scope.none if view == "unmatched"

      scope
    end

    def legacy_counts
      activity_scope = legacy_activity_scope(filter_view: false)
      manual_scope = legacy_manual_scope(filter_view: false)
      unmatched_activity_scope = activity_scope.where(expense_entry_id: nil)
      review_manual_scope = manual_scope.where(
        "expense_entries.actual_amount IS NULL OR (expense_entries.source_account_id IS NULL AND expense_entries.destination_account_id IS NULL)"
      )
      {
        "review" => unmatched_activity_scope.count + review_manual_scope.count,
        "all" => activity_scope.count + manual_scope.count,
        "unmatched" => unmatched_activity_scope.count,
        "imports" => import_scope.count
      }
    end

    def import_scope
      scope = user.account_activity_imports
      account_id.present? ? scope.where(account_id: account_id) : scope
    end

    def missing_account_discrepancies
      @missing_account_discrepancies ||= begin
        if workspace.blank?
          {}
        else
          workspace.migration_discrepancies
            .status_open
            .where(legacy_record_type: "ExpenseEntry", code: Platform::TargetBackfill::ResolveMissingAccount::ERROR_CODE)
            .index_by(&:legacy_record_id)
        end
      end
    end

    def matching_options
      return [] unless target_reads?

      items = workspace.budget_items
        .where(state: "open")
        .joins(:budget_period)
        .where(budget_periods: { state: %w[open reopened] })
        .includes(:budget_period)
        .order(scheduled_on: :desc, created_at: :desc)
        .limit(200)
        .to_a
      allocation_totals = workspace.budget_allocations
        .where(budget_item_id: items.map(&:id))
        .group(:budget_item_id)
        .sum(:amount)
      items.filter_map do |item|
        remaining = [ item.planned_amount - allocation_totals.fetch(item.id, 0).to_d, 0 ].max
        next unless remaining.positive?

        label = [
          item.budget_period.starts_on.strftime("%b %Y"),
          item.name_snapshot.presence || item.payee_snapshot.presence || item.category_snapshot.presence || "Planned item",
          ApplicationController.helpers.number_to_currency(remaining)
        ].join(" · ")
        MatchingOption.new(id: item.id, label: label, flow_kind: item.flow_kind, remaining_amount: remaining)
      end
    end

    def provider_counts
      @provider_counts ||= provider_scope.group(:state, :pending).count
    end

    def provider_scope
      return ProviderTransaction.none unless workspace
      scope = workspace.provider_transactions.joins(:connected_account).where(connected_accounts: { state: "mapped" }).where.not(connected_accounts: { account_id: nil })
      scope = scope.where(connected_accounts: { account_id: account_id }) if account_id
      scope = scope.where("COALESCE(provider_transactions.posted_at, provider_transactions.transacted_at) >= ?", starts_on.in_time_zone(workspace.time_zone)) if starts_on
      scope = scope.where("COALESCE(provider_transactions.posted_at, provider_transactions.transacted_at) < ?", ends_on.next_day.in_time_zone(workspace.time_zone)) if ends_on
      scope
    end

    def workspace
      @workspace ||= BudgetWorkspace.find_by(legacy_owner_user_id: user.id)
    end

    def target_reads?
      workspace&.target_reads_enabled?
    end

    def parse_date(value)
      Date.iso8601(value.to_s) if value.present?
    rescue Date::Error
      nil
    end
  end
end
