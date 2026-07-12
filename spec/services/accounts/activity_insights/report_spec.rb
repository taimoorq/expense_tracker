require "rails_helper"

RSpec.describe Accounts::ActivityInsights::Report do
  def activity(import, description:, date:, amount:, category: "Services", activity_type: "Sale")
    decimal = amount.to_d
    create(
      :account_activity,
      account_activity_import: import,
      account: import.account,
      transaction_on: date,
      posted_on: date,
      description: description,
      category: category,
      activity_type: activity_type,
      raw_amount: -decimal,
      amount: decimal,
      account_delta: -decimal
    )
  end

  it "builds merchant, interest, active subscription, and past subscription views from imported rows" do
    user = create(:user)
    account = create(:account, user: user, kind: :credit_card, name: "Rewards Card")
    import = create(:account_activity_import, account: account, started_on: Date.new(2026, 1, 1), ended_on: Date.new(2026, 7, 5))

    activity(import, description: "CLOUDFLARE", date: Date.new(2026, 5, 2), amount: 10.77, category: "Bills & Utilities")
    activity(import, description: "CLOUDFLARE", date: Date.new(2026, 6, 2), amount: 10.77, category: "Bills & Utilities")
    activity(import, description: "CLOUDFLARE", date: Date.new(2026, 7, 2), amount: 10.77, category: "Bills & Utilities")
    activity(import, description: "OLDSTREAM SUBSCRIPTION", date: Date.new(2026, 1, 10), amount: 19.99, category: "Entertainment")
    activity(import, description: "OLDSTREAM SUBSCRIPTION", date: Date.new(2026, 2, 10), amount: 19.99, category: "Entertainment")
    activity(import, description: "OLDSTREAM SUBSCRIPTION", date: Date.new(2026, 3, 10), amount: 19.99, category: "Entertainment")
    activity(import, description: "PURCHASE INTEREST CHARGE", date: Date.new(2026, 7, 1), amount: 100, category: "Fees & Adjustments", activity_type: "Fee")
    activity(import, description: "GIANT FOOD INC #198 POTOMAC MD01308Q", date: Date.new(2026, 7, 3), amount: 50, category: "Supermarkets")

    report = described_class.new(account: account).call

    cloudflare = report.fetch(:merchant_rollups).find { |rollup| rollup.fetch(:merchant) == "CLOUDFLARE" }
    expect(cloudflare).to include(total: "32.31".to_d, count: 3)

    expect(report.fetch(:interest_fee_rollups).first).to include(type: :interest, total: 100.to_d, count: 1)
    expect(report.fetch(:active_subscription_candidates).map { |candidate| candidate.fetch(:merchant) }).to include("CLOUDFLARE")
    expect(report.fetch(:past_subscription_candidates).map { |candidate| candidate.fetch(:merchant) }).to include("OLDSTREAM SUBSCRIPTION")
    expect(report.fetch(:active_subscription_candidates).map { |candidate| candidate.fetch(:merchant) }).not_to include(a_string_matching(/GIANT FOOD/))
  end
end
