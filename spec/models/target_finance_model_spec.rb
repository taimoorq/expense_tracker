require "rails_helper"

RSpec.describe "target financial model" do
  it "keeps planned intent separate from allocated actuals" do
    workspace = create(:budget_workspace)
    item = create(:budget_item, budget_workspace: workspace, planned_amount: 125)
    transaction = create(:financial_transaction, budget_workspace: workspace, gross_amount: 80)
    create(
      :budget_allocation,
      budget_workspace: workspace,
      budget_item: item,
      financial_transaction: transaction,
      amount: 80
    )

    expect(item.reload.allocated_amount).to eq(80)
    expect(item.remaining_amount).to eq(45)
    expect(transaction.reload.allocated_amount).to eq(80)
    expect(transaction.available_to_allocate).to eq(0)
  end

  it "rejects a currency that differs from the workspace" do
    workspace = create(:budget_workspace, default_currency_code: "USD")
    period = build(:budget_period, budget_workspace: workspace, currency_code: "EUR")

    expect(period).not_to be_valid
    expect(period.errors[:currency_code]).to include("must match the workspace currency")
  end

  it "retains append-only audit evidence" do
    workspace = create(:budget_workspace)
    event = AuditEvent.create!(
      budget_workspace: workspace,
      entity_type: "BudgetItem",
      entity_id: SecureRandom.uuid,
      action: "create",
      event_at: Time.current
    )

    expect(event).to be_readonly
    expect { event.update!(action: "edit") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { event.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "requires terminal operation runs to record completion" do
    operation = build(:operation_run, state: "succeeded", completed_at: nil)

    expect(operation).not_to be_valid
    expect(operation.errors[:completed_at]).to include("is required when complete")
  end

  it "rejects completion timestamps on nonterminal operation runs" do
    operation = build(:operation_run, state: "running", completed_at: Time.current)

    expect(operation).not_to be_valid
    expect(operation.errors[:completed_at]).to include("must be blank before completion")
  end

  it "keeps every import completion timestamp aligned with its terminal state" do
    import_batch = build(:import_batch, status: "previewed", committed_at: Time.current)

    expect(import_batch).not_to be_valid
    expect(import_batch.errors[:committed_at]).to include("must be blank before committed")

    import_batch.assign_attributes(status: "failed", committed_at: nil, failed_at: nil)
    expect(import_batch).not_to be_valid
    expect(import_batch.errors[:failed_at]).to include("is required when failed")

    import_batch.assign_attributes(status: "reverting", committed_at: Time.current)
    expect(import_batch).to be_valid
  end
end
