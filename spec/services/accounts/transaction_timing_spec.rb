require "rails_helper"

RSpec.describe Accounts::TransactionTiming do
  let(:user) { create(:user) }
  let(:month) { create(:budget_month, user: user, month_on: Date.new(2026, 9, 1)) }

  it "orders untimed credits, precise activity, then untimed debits regardless of creation order" do
    debit = create(:expense_entry, budget_month: month, occurred_on: Date.new(2026, 9, 23), section: :fixed)
    income = create(:expense_entry, budget_month: month, occurred_on: debit.occurred_on, section: :income)
    timed_income = create(:expense_entry, budget_month: month, occurred_on: debit.occurred_on, section: :income, transaction_time: "14:00")
    timed_debit = create(:expense_entry, budget_month: month, occurred_on: debit.occurred_on, section: :fixed, transaction_time: "09:15")
    expected = [ income, timed_debit, timed_income, debit ]
    expect(month.expense_entries.chronological.to_a).to eq(expected)
    expect(month.expense_entries.to_a.sort_by(&:chronological_key)).to eq(expected)
    expect(income.occurred_at).to be_nil
    expect(debit.occurred_at).to be_nil
  end

  it "retains an entered clock time on date edits and permits clearing it" do
    entry = create(:expense_entry, budget_month: month, occurred_on: Date.new(2026, 9, 22), transaction_time: "10:30")
    entry.reload.update!(occurred_on: Date.new(2026, 9, 23))
    expect(entry.occurred_at).to eq(Time.utc(2026, 9, 23, 10, 30))
    entry.update!(transaction_time: "")
    expect(entry.occurred_at).to be_nil
  end

  it "uses local midnight boundaries on short and long DST days" do
    [ Date.new(2026, 3, 8), Date.new(2026, 11, 1) ].each do |day|
      start = described_class.at(date: day, incoming: true, zone_name: "America/New_York")
      finish = described_class.at(date: day, incoming: false, zone_name: "America/New_York")
      expect(start.hour).to eq(0)
      expect(finish.strftime("%H:%M:%S.%6N")).to eq("23:59:59.999999")
      expect(finish.to_date).to eq(day)
    end
    expect { described_class.parse(date: Date.new(2026, 3, 8), clock: "02:30", zone_name: "America/New_York") }.to raise_error(ArgumentError, /does not exist/)
    expect { described_class.parse(date: Date.new(2026, 11, 1), clock: "01:30", zone_name: "America/New_York") }.to raise_error(ArgumentError, /occurs twice/)
  end
end
