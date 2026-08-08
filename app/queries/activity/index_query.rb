module Activity
  class IndexQuery
    VIEWS = %w[review all unmatched imports].freeze
    LIMIT = 100

    Row = Data.define(
      :id, :occurred_on, :description, :account, :amount, :direction, :source,
      :state, :matched, :detail_path, :transaction_id, :allocation_id, :available_amount,
      :migration_discrepancy_id
    )
    MatchingOption = Data.define(:id, :label, :flow_kind, :remaining_amount)
    Result = Data.define(
      :view, :rows, :counts, :accounts, :imports, :limited, :calculation_version,
      :target_mode, :matching_options, :account_id, :starts_on, :ends_on, :direction,
      :transaction_id, :actions_available
    )

    def self.call(user:, view: nil, account_id: nil, starts_on: nil, ends_on: nil, direction: nil, transaction_id: nil)
      new(
        user: user,
        view: view,
        account_id: account_id,
        starts_on: starts_on,
        ends_on: ends_on,
        direction: direction,
        transaction_id: transaction_id
      ).call
    end

    def initialize(user:, view:, account_id:, starts_on:, ends_on:, direction:, transaction_id:)
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
        view: view,
        rows: selected_rows.first(LIMIT),
        counts: counts,
        accounts: user.accounts.active_first.to_a,
        imports: import_scope.includes(:account).recent_first.limit(25).to_a,
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

    attr_reader :account_id, :direction, :ends_on, :starts_on, :transaction_id, :user, :view

    def filtered_rows
      view == "imports" ? [] : all_rows
    end

    def counts
      @counts ||= target_reads? ? target_counts : legacy_counts
    end

    def all_rows
      @all_rows ||= (target_reads? ? target_rows : legacy_rows).sort_by do |row|
        [ row.occurred_on || Date.new(1970, 1, 1), row.id ]
      end.reverse
    end

    def target_rows
      target_scope_for_view
        .includes(:budget_allocations, account_postings: :account)
        .order(effective_on: :desc, created_at: :desc)
        .limit(LIMIT + 1)
        .map do |transaction|
          posting = if account_id.present?
            transaction.account_postings.find { |candidate| candidate.account_id.to_s == account_id.to_s }
          else
            transaction.account_postings.first
          end
          account = posting&.account
          matched = transaction.budget_allocations.any?
          allocation = transaction.budget_allocations.first
          available_amount = [ transaction.gross_amount - transaction.budget_allocations.sum(&:amount), 0 ].max
          needs_review = transaction.state_pending? ||
            (transaction.state_posted? && transaction.origin_kind_institution_import? && !matched)
          Row.new(
            id: transaction.id,
            occurred_on: transaction.effective_on,
            description: transaction.description,
            account: account,
            amount: account_id.present? ? posting&.amount.to_d.abs : transaction.gross_amount,
            direction: account_id.present? ? (posting&.amount.to_d.positive? ? "income" : "outflow") : transaction.flow_kind,
            source: transaction.origin_kind == "institution_import" ? "Imported" : "Manual",
            state: needs_review ? "needs_review" : transaction.state == "posted" ? "reviewed" : transaction.state,
            matched: matched,
            detail_path: account && Rails.application.routes.url_helpers.account_path(account, view: "activity"),
            transaction_id: transaction.id,
            allocation_id: allocation&.id,
            available_amount: available_amount,
            migration_discrepancy_id: nil
          )
        end
    end

    def legacy_rows
      activities = legacy_activity_scope.includes(:account, :expense_entry).recent_first.limit(LIMIT + 1).to_a
      imported = activities.map do |activity|
        matched = activity.expense_entry_id.present?
        Row.new(
          id: activity.id,
          occurred_on: activity.transaction_on,
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
          migration_discrepancy_id: nil
        )
      end
      manual = legacy_manual_scope
        .includes(:source_account, :destination_account)
        .order(occurred_on: :desc, created_at: :desc)
        .limit(LIMIT + 1)
        .map do |entry|
          account = entry.source_account || entry.destination_account
          needs_review = entry.actual_amount.blank? || account.blank?
          Row.new(
            id: entry.id,
            occurred_on: entry.occurred_on,
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
            migration_discrepancy_id: missing_account_discrepancies[entry.id]&.id
          )
        end
      imported + manual
    end

    def target_scope_for_view
      case view
      when "review" then target_review_scope
      when "unmatched" then target_unmatched_scope
      else target_base_scope
      end
    end

    def target_base_scope
      scope = workspace.financial_transactions
      scope = scope.where(id: transaction_id) if transaction_id.present?
      scope = scope.where(effective_on: starts_on..) if starts_on
      scope = scope.where(effective_on: ..ends_on) if ends_on
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

    def legacy_activity_scope
      scope = user.account_activities
      scope = scope.where(account_id: account_id) if account_id.present?
      scope = scope.where(transaction_on: starts_on..) if starts_on
      scope = scope.where(transaction_on: ..ends_on) if ends_on
      scope = scope.where("account_delta > 0") if direction == "incoming"
      scope = scope.where("account_delta < 0") if direction == "outgoing"
      case view
      when "review", "unmatched" then scope.where(expense_entry_id: nil)
      else scope
      end
    end

    def legacy_manual_scope
      scope = user.expense_entries
        .paid
        .left_joins(:account_activities)
        .where(account_activities: { id: nil })
      scope = scope.where(occurred_on: starts_on..) if starts_on
      scope = scope.where(occurred_on: ..ends_on) if ends_on
      if account_id.present?
        scope = scope.where("expense_entries.source_account_id = :id OR expense_entries.destination_account_id = :id", id: account_id)
      end
      return scope.where("expense_entries.actual_amount IS NULL OR (expense_entries.source_account_id IS NULL AND expense_entries.destination_account_id IS NULL)") if view == "review"
      return scope.none if view == "unmatched"

      scope
    end

    def legacy_counts
      activity_scope = user.account_activities
      manual_scope = user.expense_entries
        .paid
        .left_joins(:account_activities)
        .where(account_activities: { id: nil })
      if account_id.present?
        activity_scope = activity_scope.where(account_id: account_id)
        manual_scope = manual_scope.where(
          "expense_entries.source_account_id = :id OR expense_entries.destination_account_id = :id",
          id: account_id
        )
      end
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
