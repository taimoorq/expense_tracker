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
end
