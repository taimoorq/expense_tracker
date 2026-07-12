require "rails_helper"

RSpec.describe "page load indexes" do
  def index_by_name(table_name, index_name)
    ActiveRecord::Base.connection.indexes(table_name).index_by(&:name).fetch(index_name)
  end

  it "supports the month timeline and entry refresh ordering" do
    index = index_by_name(:expense_entries, "index_expense_entries_on_month_chronological")

    expect(index.columns).to eq(%w[budget_month_id occurred_on created_at])
  end

  it "supports account detail pages showing recent linked entries" do
    index = index_by_name(:expense_entries, "index_expense_entries_on_source_account_recent")

    expect(index.columns).to eq(%w[source_account_id occurred_on created_at])
    expect(index.where).to include("source_account_id IS NOT NULL")
  end

  it "supports imported account activity history and idempotency" do
    chronological_index = index_by_name(:account_activities, "index_account_activities_on_account_chronological")
    fingerprint_index = index_by_name(:account_activities, "index_account_activities_on_account_id_and_fingerprint")

    expect(chronological_index.columns).to eq(%w[account_id transaction_on created_at])
    expect(fingerprint_index.columns).to eq(%w[account_id fingerprint])
    expect(fingerprint_index.unique).to be(true)
  end

  it "supports recurring-entry auto completion for a signed-in user" do
    index = index_by_name(:expense_entries, "index_expense_entries_on_user_due_recurring")

    expect(index.columns).to eq(%w[user_id status occurred_on])
    expect(index.where).to include("occurred_on IS NOT NULL")
    expect(index.where).to include("source_file")
    expect(index.where).to include("pay_schedule")
  end

  it "enforces durable generated recurring entry identity" do
    index = index_by_name(:expense_entries, "index_expense_entries_on_generated_entry_key_unique")

    expect(index.columns).to eq(%w[generated_entry_key])
    expect(index.unique).to be(true)
    expect(index.where).to include("generated_entry_key IS NOT NULL")
  end

  it "supports account and recurring-template list ordering" do
    expect(index_by_name(:accounts, "index_accounts_on_user_active_name").columns).to eq(%w[user_id active name])
    expect(index_by_name(:pay_schedules, "index_pay_schedules_on_user_name").columns).to eq(%w[user_id name])
    expect(index_by_name(:subscriptions, "index_subscriptions_on_user_due_day_name").columns).to eq(%w[user_id due_day name])
    expect(index_by_name(:monthly_bills, "index_monthly_bills_on_user_kind_due_day_name").columns).to eq(%w[user_id kind due_day name])
    expect(index_by_name(:payment_plans, "index_payment_plans_on_user_due_day_name").columns).to eq(%w[user_id due_day name])
    expect(index_by_name(:credit_cards, "index_credit_cards_on_user_priority_name").columns).to eq(%w[user_id priority name])
  end
end
