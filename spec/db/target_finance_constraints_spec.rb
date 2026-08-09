require "rails_helper"

RSpec.describe "target financial database constraints" do
  def foreign_key(table_name, name)
    ActiveRecord::Base.connection.foreign_keys(table_name).find { |key| key.name == name }
  end

  it "installs workspace and currency composite ownership keys" do
    period_key = foreign_key(:budget_items, "fk_items_period_currency")
    posting_key = foreign_key(:account_postings, "fk_postings_account_currency")

    expect(period_key.column).to eq(%w[budget_period_id budget_workspace_id currency_code])
    expect(period_key.primary_key).to eq(%w[id budget_workspace_id currency_code])
    expect(posting_key.column).to eq(%w[account_id budget_workspace_id currency_code])
    expect(posting_key).to be_validated
  end

  it "rejects a cross-workspace budget period below Active Record" do
    first_workspace = create(:budget_workspace)
    other_workspace = create(:budget_workspace)
    period = create(:budget_period, budget_workspace: first_workspace)
    timestamp = Time.current

    expect do
      BudgetItem.insert_all!(
        [
          {
            budget_workspace_id: other_workspace.id,
            budget_period_id: period.id,
            flow_kind: "outflow",
            budget_group: "variable",
            planned_amount: 10,
            currency_code: "USD",
            state: "open",
            origin_kind: "migration",
            lock_version: 0,
            created_at: timestamp,
            updated_at: timestamp
          }
        ]
      )
    end.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "rejects an account currency that differs from its workspace below Active Record" do
    user = create(:user)
    workspace = create(:budget_workspace, default_currency_code: "USD")
    timestamp = Time.current

    expect do
      Account.insert_all!(
        [
          {
            user_id: user.id,
            budget_workspace_id: workspace.id,
            name: "Euro account",
            kind: Account.kinds.fetch("checking"),
            active: true,
            include_in_net_worth: true,
            include_in_cash: true,
            currency_code: "EUR",
            lock_version: 0,
            created_at: timestamp,
            updated_at: timestamp
          }
        ]
      )
    end.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "rejects zero-value postings below Active Record" do
    workspace = create(:budget_workspace)
    account = create(:workspace_account, budget_workspace: workspace)
    transaction = create(:financial_transaction, budget_workspace: workspace)
    timestamp = Time.current

    expect do
      AccountPosting.insert_all!(
        [
          {
            budget_workspace_id: workspace.id,
            financial_transaction_id: transaction.id,
            account_id: account.id,
            amount: 0,
            currency_code: "USD",
            role: "primary",
            sequence_number: 0,
            created_at: timestamp,
            updated_at: timestamp
          }
        ]
      )
    end.to raise_error(ActiveRecord::StatementInvalid, /postings_amount_nonzero/)
  end

  it "rejects cross-owner durable import drafts below Active Record" do
    draft = create(:account_activity_import_draft)
    other_user = create(:user)

    expect do
      AccountActivityImportDraft.where(id: draft.id).update_all(user_id: other_user.id)
    end.to raise_error(ActiveRecord::InvalidForeignKey, /fk_activity_import_drafts_account_owner/)
  end

  it "requires terminal durable import draft timestamps below Active Record" do
    draft = create(:account_activity_import_draft)

    expect do
      AccountActivityImportDraft.where(id: draft.id).update_all(state: "consumed", consumed_at: nil)
    end.to raise_error(ActiveRecord::StatementInvalid, /activity_import_drafts_consumed_coherent/)
  end

  it "requires terminal staged backup timestamps below Active Record" do
    source = create(:user)
    token = Platform::BackupRestorePreviewStore.new(user: source).store(
      payload: {
        format: Platform::UserDataExport::FORMAT_NAME,
        version: 1,
        data: { preferences: { default_landing_page: "overview" } }
      },
      scopes: [ "preferences" ],
      encrypted: false
    )
    draft = Platform::BackupRestorePreviewStore.new(user: source).load_draft(token)

    expect do
      BackupRestoreDraft.where(id: draft.id).update_all(state: "consumed", consumed_at: nil)
    end.to raise_error(ActiveRecord::StatementInvalid, /backup_restore_drafts_consumed_coherent/)
  end

  invalid_state_updates = [
    [
      "requires void evidence for voided budget items",
      :budget_item,
      { state: "voided", voided_at: nil, void_reason: nil },
      "budget_items_void_state_coherent"
    ],
    [
      "rejects void evidence on open budget items",
      :budget_item,
      { state: "open", voided_at: Time.current, void_reason: "duplicate" },
      "budget_items_void_state_coherent"
    ],
    [
      "requires void evidence for voided transactions",
      :financial_transaction,
      { state: "voided", voided_at: nil, void_reason: nil },
      "transactions_void_state_coherent"
    ],
    [
      "requires closed workspaces to record when they closed",
      :budget_workspace,
      { status: "closed", closed_at: nil },
      "workspaces_closed_state_coherent"
    ],
    [
      "rejects removal timestamps on active memberships",
      :workspace_membership,
      { status: "active", removed_at: Time.current },
      "memberships_removed_state_coherent"
    ],
    [
      "rejects completion timestamps on pending operations",
      :operation_run,
      { state: "pending", completed_at: Time.current },
      "operations_completion_state_coherent"
    ],
    [
      "requires terminal transfer runs to record completion",
      :data_transfer_run,
      { state: "succeeded", completed_at: nil },
      "transfer_runs_completion_state_coherent"
    ],
    [
      "rejects commit timestamps on previewed import batches",
      :import_batch,
      { status: "previewed", committed_at: Time.current },
      "import_batches_terminal_state_coherent"
    ],
    [
      "requires failed import batches to record failure time",
      :import_batch,
      { status: "failed", failed_at: nil },
      "import_batches_terminal_state_coherent"
    ]
  ]

  invalid_state_updates.each do |description, factory_name, attributes, constraint_name|
    it "#{description} below Active Record" do
      record = create(factory_name)

      expect do
        record.class.where(id: record.id).update_all(attributes)
      end.to raise_error(ActiveRecord::StatementInvalid, /#{constraint_name}/)
    end
  end
end
