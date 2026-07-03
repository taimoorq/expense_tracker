require "rails_helper"

RSpec.describe CsvBudgetImporter do
  it "imports transactions into the provided user's months only" do
    user = create(:user)
    other_user = create(:user)
    create(:budget_month, user: other_user, month_on: Date.new(2026, 3, 1), label: "March 2026")

    file = Tempfile.new([ "budget-importer", ".csv" ])
    file.write(<<~CSV)
      Month,Date,Section,Category,Payee,Planned Amount,Actual Amount,Account,Status,Need or Want,Notes
      2026-03,2026-03-10,fixed,Utilities,Pepco,95.18,,Checking,planned,Need,Importer spec
    CSV
    file.rewind

    upload = Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "budget.csv")
    result = described_class.new(file: upload, user: user).call

    expect(result).to include(ok: true, months: 1, entries: 1)
    expect(user.budget_months.find_by(month_on: Date.new(2026, 3, 1))).to be_present
    expect(ExpenseEntry.where(user: user, payee: "Pepco").count).to eq(1)
    expect(ExpenseEntry.where(user: other_user, payee: "Pepco")).to be_empty
  ensure
    file.close
    file.unlink
  end

  it "returns row-level errors without importing invalid values" do
    user = create(:user)

    file = Tempfile.new([ "budget-importer-invalid", ".csv" ])
    file.write(<<~CSV)
      Month,Date,Section,Category,Payee,Planned Amount,Actual Amount,Account,Status,Need or Want,Notes
      2026-03,not-a-date,fixed,Utilities,Pepco,not-money,,Checking,planned,Need,Importer spec
    CSV
    file.rewind

    upload = Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "budget.csv")
    result = described_class.new(file: upload, user: user).call

    expect(result).to include(ok: false)
    expect(result[:errors]).to contain_exactly(
      "Row 2: Date could not be parsed.",
      "Row 2: Planned Amount could not be parsed."
    )
    expect(user.budget_months.reload).to be_empty
  ensure
    file.close
    file.unlink
  end

  it "keeps normalized values as warnings when they are importable" do
    user = create(:user)

    file = Tempfile.new([ "budget-importer-warning", ".csv" ])
    file.write(<<~CSV)
      Month,Date,Section,Category,Payee,Planned Amount,Actual Amount,Account,Status,Need or Want,Notes
      2026-03,2026-03-10,mystery,Utilities,Pepco,95.18,,Checking,unknown,Need,Importer spec
    CSV
    file.rewind

    upload = Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "budget.csv")
    result = described_class.new(file: upload, user: user).call

    expect(result).to include(ok: true, months: 1, entries: 1)
    expect(result[:warnings]).to contain_exactly(
      "Row 2: Section mystery is not recognized and will be imported as Other.",
      "Row 2: Status unknown is not recognized and will be imported as Planned."
    )
    entry = user.expense_entries.find_by!(payee: "Pepco")
    expect(entry.section).to eq("other")
    expect(entry.status).to eq("planned")
  ensure
    file.close
    file.unlink
  end

  it "imports explicit money-leaves and money-goes-to account links" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    visa = create(:account, user: user, name: "Rewards Visa", kind: :credit_card)

    file = Tempfile.new([ "budget-importer-account-flow", ".csv" ])
    file.write(<<~CSV)
      Month,Date,Section,Category,Payee,Planned Amount,Actual Amount,Money Leaves Account,Money Goes To Account,Status,Need or Want,Notes
      2026-03,2026-03-18,debt,Credit Card,Rewards Visa,250,,Checking,Rewards Visa,planned,Need,Card payment
    CSV
    file.rewind

    upload = Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "budget.csv")
    result = described_class.new(file: upload, user: user).call

    expect(result).to include(ok: true, months: 1, entries: 1)
    entry = user.expense_entries.find_by!(payee: "Rewards Visa")
    expect(entry.source_account).to eq(checking)
    expect(entry.destination_account).to eq(visa)
    expect(entry.account).to eq("Checking")
  ensure
    file.close
    file.unlink
  end

  it "warns when explicit account-link columns do not match saved accounts" do
    user = create(:user)

    file = Tempfile.new([ "budget-importer-unresolved-account-flow", ".csv" ])
    file.write(<<~CSV)
      Month,Date,Section,Category,Payee,Planned Amount,Actual Amount,Money Leaves Account,Money Goes To Account,Status,Need or Want,Notes
      2026-03,2026-03-18,debt,Credit Card,Rewards Visa,250,,Checking,Rewards Visa,planned,Need,Card payment
    CSV
    file.rewind

    upload = Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "budget.csv")
    result = described_class.new(file: upload, user: user).call

    expect(result).to include(ok: true, months: 1, entries: 1)
    expect(result[:warnings]).to contain_exactly(
      "Row 2: Money leaves / activity account Checking does not match a saved account and will be kept as a manual account label.",
      "Row 2: Money goes to Rewards Visa does not match a saved account and will be left unlinked."
    )
    entry = user.expense_entries.find_by!(payee: "Rewards Visa")
    expect(entry.source_account).to be_nil
    expect(entry.destination_account).to be_nil
    expect(entry.account).to eq("Checking")
  ensure
    file.close
    file.unlink
  end

  it "previews exact duplicates and skips them during import" do
    user = create(:user)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    create(:expense_entry, budget_month: month, user: user, occurred_on: Date.new(2026, 3, 10), section: :fixed, category: "Utilities", payee: "Pepco", planned_amount: 95.18)

    file = Tempfile.new([ "budget-importer-duplicate", ".csv" ])
    file.write(<<~CSV)
      Month,Date,Section,Category,Payee,Planned Amount,Actual Amount,Account,Status,Need or Want,Notes
      2026-03,2026-03-10,fixed,Utilities,Pepco,95.18,,Checking,planned,Need,Importer spec
    CSV
    file.rewind

    upload = Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "budget.csv")
    importer = described_class.new(file: upload, user: user)
    preview = importer.preview

    expect(preview).to include(ok: true, entries: 0, duplicates: 1)
    expect(preview[:warnings].first).to include("duplicate")
    expect { importer.call }.not_to change(ExpenseEntry, :count)
  ensure
    file.close
    file.unlink
  end
end
