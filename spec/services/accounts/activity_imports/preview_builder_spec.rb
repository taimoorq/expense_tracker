require "rails_helper"

RSpec.describe Accounts::ActivityImports::PreviewBuilder do
  def uploaded_fixture(filename)
    path = Rails.root.join("test/fixtures/files/account_activity/#{filename}")
    Rack::Test::UploadedFile.new(path, "text/csv", original_filename: filename)
  end

  it "previews signed activity files with type-driven direction" do
    user = create(:user)
    account = create(:account, user: user)

    preview = described_class.new(user: user, account: account, file: uploaded_fixture("signed_amounts_with_type.csv")).call

    expect(preview).to include(ok: true, rows_count: 472, imported_count: 472, duplicate_count: 0)
    expect(preview[:amount_strategy]).to eq("type_column")
    expect(preview[:sample_rows].first[:account_delta].to_d).to be_positive
  end

  it "previews positive-charge files with inverted amount direction" do
    user = create(:user)
    account = create(:account, user: user)

    preview = described_class.new(user: user, account: account, file: uploaded_fixture("positive_charges.csv")).call

    expect(preview).to include(ok: true, rows_count: 318, imported_count: 318, duplicate_count: 0)
    expect(preview[:amount_strategy]).to eq("charges_are_positive")
    expect(preview[:sample_rows].first[:raw_amount].to_d).to be_positive
    expect(preview[:sample_rows].first[:account_delta].to_d).to be_negative
  end

  it "finds the real header after preamble rows" do
    user = create(:user)
    account = create(:account, user: user, kind: :credit_card)

    preview = described_class.new(user: user, account: account, file: uploaded_fixture("preamble_card_activity.csv")).call

    expect(preview).to include(ok: true, rows_count: 197, imported_count: 197, duplicate_count: 0)
    expect(preview[:header_row_number]).to eq(5)
    expect(preview[:amount_strategy]).to eq("type_column")
    expect(preview[:institution_balance].to_d).to be_negative
    expect(preview[:institution_balance_as_of]).to eq("2026-06-30")
    expect(preview[:metadata]).to include(
      "institution_name" => "Sample Card Services",
      "institution_balance_as_of" => "2026-06-30"
    )
    expect(preview[:metadata]["institution_balance"].to_d).to be_negative
  end

  it "previews BOA bank activity and skips non-activity balance rows" do
    user = create(:user)
    account = create(:account, user: user, kind: :checking)

    preview = described_class.new(user: user, account: account, file: uploaded_fixture("boa_bank_activity.csv")).call

    expect(preview).to include(ok: true, rows_count: 199, imported_count: 199, duplicate_count: 0)
    expect(preview[:header_row_number]).to eq(7)
    expect(preview[:headers]).to eq([ "Date", "Description", "Amount", "Running Bal." ])
    expect(preview[:column_mapping]).to include(transaction_on: "Date", description: "Description", raw_amount: "Amount")
    expect(preview[:amount_strategy]).to eq("charges_are_negative")
    expect(preview[:institution_name]).to eq("Sample Bank of America")
    expect(preview[:institution_balance]).to eq("22149.46")
    expect(preview[:institution_balance_as_of]).to eq("2026-07-02")
    expect(preview[:metadata]).to include(
      "institution_balance_label" => "Ending balance",
      "institution_balance_as_of" => "2026-07-02"
    )
    expect(preview[:sample_rows].first[:row_number]).to eq(9)
    expect(preview[:sample_rows].first[:raw_amount].to_d).to be_negative
    expect(preview[:sample_rows].first[:account_delta].to_d).to be_negative
  end

  it "marks existing fingerprints as duplicates on repeated import" do
    user = create(:user)
    account = create(:account, user: user)
    first_preview = described_class.new(user: user, account: account, file: uploaded_fixture("positive_charges.csv")).call

    result = Accounts::ActivityImports::Importer.new(user: user, account: account, preview: first_preview).call
    expect(result).to include(ok: true, imported_count: 318, duplicate_count: 0)

    second_preview = described_class.new(user: user, account: account, file: uploaded_fixture("positive_charges.csv")).call

    expect(second_preview).to include(ok: true, rows_count: 318, imported_count: 0, duplicate_count: 318)
  end
end
