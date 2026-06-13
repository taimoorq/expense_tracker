require "rails_helper"

RSpec.describe Accounts::DetailPage do
  it "composes account detail data including credit card progress and connected templates" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    card = create(:account, user: user, name: "Rewards Visa", kind: :credit_card)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 6, 1), label: "June 2026")
    create(:account_snapshot, account: card, recorded_on: Date.new(2026, 6, 1), balance: -500)
    create(:credit_card, user: user, name: "Rewards Visa", payment_account: checking, linked_account: card)
    create(
      :expense_entry,
      budget_month: month,
      user: user,
      source_account: checking,
      destination_account: card,
      occurred_on: Date.new(2026, 6, 10),
      section: :debt,
      status: :paid,
      actual_amount: 100
    )

    detail_page = described_class.new(account: card, as_of: Date.new(2026, 6, 15)).call

    expect(detail_page.fetch(:balance_summary).fetch(:current_balance)).to eq(-400.to_d)
    expect(detail_page.fetch(:credit_card_progress).fetch(:paid_down_this_month)).to eq(100.to_d)
    expect(detail_page.fetch(:linked_entries).size).to eq(1)
    expect(detail_page.fetch(:linked_entries_net)).to eq(100.to_d)
    expect(detail_page.fetch(:connected_templates_count)).to eq(1)
    expect(detail_page.fetch(:connected_templates).fetch("Credit Cards").first.name).to eq("Rewards Visa")
  end
end
