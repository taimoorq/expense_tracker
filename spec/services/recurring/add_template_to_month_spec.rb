require "rails_helper"

RSpec.describe Recurring::AddTemplateToMonth do
  let(:user) { create(:user) }
  let(:account) { create(:account, user: user) }
  let(:month) { create(:budget_month, user: user, month_on: Date.new(2026, 9, 1)) }
  let(:template) { create(:subscription, user: user, name: "Cloud", amount: 12, due_day: 8, linked_account: account) }
  subject(:command) { described_class.new(user: user, template: template, budget_month: month) }

  it "adds only this template as planned, preserves the linked account, and replays" do
    create(:subscription, user: user, name: "Unrelated")
    digest = command.preview.digest
    expect(command.call(expected_digest: digest).status).to eq(:added)
    expect(command.call(expected_digest: digest).status).to eq(:already_present)
    expect(month.expense_entries.sole).to have_attributes(source_template: template, source_account: account, status: "planned", actual_amount: nil)
    expect(FinancialTransaction.count).to eq(0)
    expect(AccountPosting.count).to eq(0)
    expect(Recurring::GenerateMonthRecurringEntries.new(budget_month: month, templates: [ template ]).call).to eq(0)
  end

  it "recognizes edited and skipped source-linked items without overwriting them" do
    entry = create(:expense_entry, user: user, budget_month: month, source_template: template, occurred_on: Date.new(2026, 9, 20), payee: "Renamed", planned_amount: 99, status: "skipped")
    expect(command.preview.status).to eq(:already_present)
    expect(command.call(expected_digest: "old").entry).to eq(entry)
    expect(entry.reload).to have_attributes(status: "skipped", planned_amount: 99.to_d)
  end

  it "recognizes an existing matching manual item on another date" do
    bill = create(:monthly_bill, user: user, name: "Water", kind: :variable_bill, linked_account: account)
    create(:expense_entry, user: user, budget_month: month, source_account: account, payee: "Water", section: :manual, category: "Variable Bill", planned_amount: 95, occurred_on: Date.new(2026, 9, 25))
    preview = described_class.new(user: user, template: bill, budget_month: month).preview
    expect(preview.status).to eq(:already_present)
  end

  it "clips day 31 and respects a bill's billing months" do
    template.update!(due_day: 31)
    expect(command.preview.date).to eq(Date.new(2026, 9, 30))
    bill = create(:monthly_bill, user: user, billing_frequency: :annual, billing_months: [ 1 ])
    other = described_class.new(user: user, template: bill, budget_month: month)
    expect(other.preview.status).to eq(:not_scheduled)
    expect { other.call(expected_digest: other.preview.digest) }.to raise_error(described_class::Invalid, /not scheduled/)
  end

  it "rejects a stale preview, inactive template, and foreign month" do
    digest = command.preview.digest
    template.update!(amount: 15)
    expect { command.call(expected_digest: digest) }.to raise_error(described_class::Invalid, /changed/)
    template.update!(active: false)
    expect { command.preview }.to raise_error(described_class::Invalid, /Activate/)
    expect { described_class.new(user: user, template: template, budget_month: create(:budget_month)).preview }.to raise_error(ActiveRecord::RecordNotFound)
    expect(month.expense_entries).to be_empty
  end

  context "with target writes enabled" do
    let!(:workspace) do
      template
      month
      result = Platform::TargetBackfill::Runner.call(user: user).workspace
      result.update!(target_writes_enabled: true, target_reads_enabled: false)
      template.reload
      month.reload
      result
    end

    it "creates a mapped occurrence and item, without touching unrelated records or actuals" do
      result = command.call(expected_digest: command.preview.digest)
      expect(result.status).to eq(:added)
      expect(workspace.budget_items.sole).to have_attributes(intended_source_account: account, planned_amount: 12.to_d, state: "open")
      expect(workspace.recurring_occurrences.sole.budget_item).to eq(workspace.budget_items.sole)
      expect(workspace.financial_transactions).to be_empty
      expect(command.call(expected_digest: "replayed").status).to eq(:already_present)
    end

    it "rejects a month closed after preview even when target reads are off" do
      digest = command.preview.digest
      workspace.budget_periods.sole.update!(state: "closed")
      expect { command.call(expected_digest: digest) }.to raise_error(described_class::Invalid, /Reopen/)
      expect(month.expense_entries).to be_empty
    end

    it "rolls back month insertion when target sync fails, retaining the template" do
      allow(Platform::TargetSync::ExpenseEntryWriter).to receive(:call).and_raise(Platform::TargetSync::WriteRejected, "Cannot sync")
      expect { command.call(expected_digest: command.preview.digest) }.to raise_error(Platform::TargetSync::WriteRejected)
      expect(month.expense_entries).to be_empty
      expect(user.subscriptions).to include(template)
      expect(workspace.budget_items).to be_empty
    end
  end
end
