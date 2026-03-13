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
end
