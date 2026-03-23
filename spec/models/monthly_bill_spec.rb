require "rails_helper"

RSpec.describe MonthlyBill, type: :model do
  it "defaults monthly bills to all months" do
    bill = build(:monthly_bill, billing_months: [])

    bill.validate

    expect(bill.billing_months).to eq((1..12).to_a)
  end

  it "supports explicit semiannual billing months" do
    bill = build(:monthly_bill, billing_frequency: :semiannual, billing_months: [ 1, 7 ])

    expect(bill).to be_valid
    expect(bill.scheduled_for_month?(Date.new(2026, 1, 1))).to be(true)
    expect(bill.scheduled_for_month?(Date.new(2026, 7, 1))).to be(true)
    expect(bill.scheduled_for_month?(Date.new(2026, 3, 1))).to be(false)
  end

  it "requires the right number of billing months for the selected frequency" do
    bill = build(:monthly_bill, billing_frequency: :annual, billing_months: [ 1, 7 ])

    expect(bill).not_to be_valid
    expect(bill.errors[:billing_months]).to include("must include 1 month for annual")
  end
end
