require "rails_helper"

RSpec.describe Accounts::ActivityImports::ColumnMapper do
  it "accepts a complete Debit and Credit pair instead of one Amount column" do
    result = described_class.call([ "Status", "Date", "Description", "Debit", "Credit", "Member Name" ])

    expect(result.missing_fields).to be_empty
    expect(result.mapping).to include(
      transaction_on: "Date",
      description: "Description",
      debit_amount: "Debit",
      credit_amount: "Credit"
    )
    expect(result.extra_headers).to contain_exactly("Status", "Member Name")
  end

  it "does not accept an incomplete split amount mapping" do
    result = described_class.call([ "Date", "Description", "Debit" ])

    expect(result.missing_fields).to contain_exactly(:raw_amount)
  end
end
