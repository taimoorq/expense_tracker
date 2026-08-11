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
    expect(preview[:file_digest]).to match(/\A[0-9a-f]{64}\z/)
    expect(preview[:commit_idempotency_key]).to match(/\A[0-9a-f]{64}\z/)
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

  it "previews Citibank Costco activity with explicit Debit and Credit direction" do
    user = create(:user)
    account = create(:account, user: user, kind: :credit_card)

    preview = described_class.new(user: user, account: account, file: uploaded_fixture("citibank_costco_activity.csv")).call

    expect(preview).to include(ok: true, rows_count: 3, imported_count: 3, duplicate_count: 0)
    expect(preview[:column_mapping]).to include(debit_amount: "Debit", credit_amount: "Credit")
    expect(preview[:amount_strategy]).to eq("type_column")
    expect(preview[:amount_strategy_label]).to eq("Debit and credit columns")

    debit_row, credit_row = preview[:rows].first(2)
    expect(debit_row).to include(activity_type: "Debit", raw_amount: "42.15", amount: "42.15", account_delta: "-42.15")
    expect(credit_row).to include(activity_type: "Credit", raw_amount: "-125.0", amount: "125.0", account_delta: "125.0")
    expect(debit_row[:raw_payload]).to include("Status" => "Cleared", "Member Name" => "SAMPLE MEMBER")
  end

  it "previews headerless Best Buy Citibank activity with signed amount direction" do
    user = create(:user)
    account = create(:account, user: user, kind: :credit_card)

    preview = described_class.new(user: user, account: account, file: uploaded_fixture("citibank_best_buy_activity.csv")).call

    expect(preview).to include(ok: true, rows_count: 5, imported_count: 5, duplicate_count: 0)
    expect(preview[:headers]).to eq([ "Date", "Amount", "Description", "Details" ])
    expect(preview[:header_row_number]).to eq(1)
    expect(preview[:column_mapping]).to include(transaction_on: "Date", description: "Description", raw_amount: "Amount")
    expect(preview[:column_mapping]).not_to include(:category, :activity_type)
    expect(preview[:amount_strategy]).to eq("charges_are_positive")
    expect(preview[:metadata]).to include(
      "headerless" => true,
      "delimiter" => "tab",
      "source_format" => "best_buy_citibank_headerless_tsv"
    )

    payment_row, purchase_row = preview[:rows].first(2)
    zero_row = preview[:rows].last
    expect(payment_row).to include(raw_amount: "-100.0", amount: "100.0", account_delta: "100.0")
    expect(purchase_row).to include(raw_amount: "12.34", amount: "12.34", account_delta: "-12.34")
    expect(zero_row).to include(raw_amount: "0.0", amount: "0.0", account_delta: "0.0")
    expect(payment_row[:raw_payload]).to include("Details" => "SAMPLE PAYMENT DETAIL")
  end

  it "rejects a split amount row when both Debit and Credit are populated" do
    user = create(:user)
    account = create(:account, user: user, kind: :credit_card)
    file = Tempfile.new([ "ambiguous-citibank-activity", ".csv" ])
    file.write(<<~CSV)
      Status,Date,Description,Debit,Credit,Member Name
      Cleared,08/01/2026,SAMPLE AMBIGUOUS ROW,42.15,-10.00,SAMPLE MEMBER
    CSV
    file.rewind
    upload = Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "ambiguous.csv")

    preview = described_class.new(user: user, account: account, file: upload).call

    expect(preview[:ok]).to be(false)
    expect(preview[:errors]).to include("Row 2: Debit and Credit cannot both have amounts.")
    expect(preview[:rows]).to be_empty
  ensure
    file&.close
    file&.unlink
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

  it "returns the original committed batch when the same preview is submitted again" do
    user = create(:user)
    account = create(:account, user: user)
    preview = described_class.new(user: user, account: account, file: uploaded_fixture("positive_charges.csv")).call

    first_result = Accounts::ActivityImports::Importer.new(user: user, account: account, preview: preview).call
    second_result = Accounts::ActivityImports::Importer.new(user: user, account: account, preview: preview).call

    expect(first_result).to include(ok: true, imported_count: 318, duplicate_count: 0, replayed: false)
    expect(second_result).to include(ok: true, imported_count: 318, duplicate_count: 0, replayed: true)
    expect(second_result[:import]).to eq(first_result[:import])
    expect(user.account_activity_imports.count).to eq(1)
    expect(account.account_activities.count).to eq(318)
  end

  it "treats a row committed after preview as a duplicate without aborting the batch" do
    user = create(:user)
    account = create(:account, user: user)
    preview = described_class.new(user: user, account: account, file: uploaded_fixture("positive_charges.csv")).call
    row = preview.fetch(:rows).first
    previous_import = create(:account_activity_import, user: user, account: account)
    create(
      :account_activity,
      user: user,
      account: account,
      account_activity_import: previous_import,
      fingerprint: row.fetch(:fingerprint)
    )

    result = Accounts::ActivityImports::Importer.new(user: user, account: account, preview: preview).call

    expect(result).to include(ok: true, imported_count: 317, duplicate_count: 1, replayed: false)
    expect(account.account_activities.count).to eq(318)
  end
end
