require "rails_helper"

RSpec.describe Platform::LegacyGeneratedEntryKeyRepair do
  it "previews deterministic repairs without mutating entries" do
    user = create(:user)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1))
    bill = create(:monthly_bill, user: user)
    card = create(:credit_card, user: user)
    bill_entry = create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_file: bill.template_source_file,
      source_template: bill,
      generated_entry_key: nil
    )
    card_entry = create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_file: CreditCard.template_source_file,
      source_template: card,
      generated_entry_key: nil
    )

    result = described_class.call

    expect(result).to be_clean
    expect(result.candidate_count).to eq(2)
    expect(result.repairable_count).to eq(2)
    expect(result.repaired_count).to eq(0)
    expect(bill_entry.reload.generated_entry_key).to be_nil
    expect(card_entry.reload.generated_entry_key).to be_nil
  end

  it "applies canonical keys and is idempotent" do
    user = create(:user)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1))
    bill = create(:monthly_bill, user: user)
    entry = create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_file: bill.template_source_file,
      source_template: bill,
      generated_entry_key: nil
    )

    result = described_class.call(apply: true)
    replay = described_class.call(apply: true)

    expect(result.repaired_count).to eq(1)
    expect(entry.reload.generated_entry_key).to eq(
      bill.generated_entry_key(month_on: month.month_on, occurred_on: entry.occurred_on)
    )
    expect(replay.candidate_count).to eq(0)
    expect(replay.repaired_count).to eq(0)
  end

  it "reports key conflicts and incomplete provenance without overwriting either row" do
    user = create(:user)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1))
    bill = create(:monthly_bill, user: user)
    canonical_key = bill.generated_entry_key(month_on: month.month_on, occurred_on: month.month_on)
    create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_file: bill.template_source_file,
      source_template: bill,
      generated_entry_key: canonical_key
    )
    conflict = create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_file: bill.template_source_file,
      source_template: bill,
      generated_entry_key: nil
    )
    unsupported = create(
      :expense_entry,
      user: user,
      budget_month: month,
      occurred_on: nil,
      source_file: bill.template_source_file,
      source_template: bill,
      generated_entry_key: nil
    )

    result = described_class.call(apply: true)

    expect(result).not_to be_clean
    expect(result.conflict_count).to eq(1)
    expect(result.unsupported_count).to eq(1)
    expect(result.conflict_samples).to include(hash_including(entry_id: conflict.id))
    expect(result.unsupported_samples).to include(hash_including(entry_id: unsupported.id))
    expect(conflict.reload.generated_entry_key).to be_nil
    expect(unsupported.reload.generated_entry_key).to be_nil
  end
end
