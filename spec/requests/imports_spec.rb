require "rails_helper"

RSpec.describe "CSV imports", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "imports rows into the signed in user's months only" do
    file = Tempfile.new([ "budget-import", ".csv" ])
    file.write(<<~CSV)
      Month,Date,Section,Category,Payee,Planned Amount,Actual Amount,Account,Status,Need or Want,Notes
      2026-03,2026-03-02,fixed,Utilities,Pepco,91.22,,Checking,planned,Need,Imported row
    CSV
    file.rewind

    upload = Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "import.csv")

    expect do
      post import_csv_path, params: { file: upload }
    end.to change(user.budget_months, :count).by(1)
       .and change(ExpenseEntry.where(user: user), :count).by(1)

    expect(response).to redirect_to(budget_months_path)
    expect(flash[:notice]).to include("Import complete")
    expect(BudgetMonth.last.user).to eq(user)
  ensure
    file.close
    file.unlink
  end

  it "previews row errors without mutating data" do
    file = Tempfile.new([ "budget-import-preview-error", ".csv" ])
    file.write(<<~CSV)
      Month,Date,Section,Category,Payee,Planned Amount,Actual Amount,Account,Status,Need or Want,Notes
      2026-03,not-a-date,fixed,Utilities,Pepco,91.22,,Checking,planned,Need,Imported row
    CSV
    file.rewind

    upload = Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "import.csv")

    expect do
      post preview_import_csv_path, params: { file: upload }
    end.not_to change(ExpenseEntry, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Row 2: Date could not be parsed.")
    expect(response.body).to include("No data was changed.")
    expect(user.budget_months.reload).to be_empty
  ensure
    file.close
    file.unlink
  end

  it "imports from a valid CSV preview token" do
    file = Tempfile.new([ "budget-import-preview", ".csv" ])
    file.write(<<~CSV)
      Month,Date,Section,Category,Payee,Planned Amount,Actual Amount,Account,Status,Need or Want,Notes
      2026-03,2026-03-02,fixed,Utilities,Pepco,91.22,,Checking,planned,Need,Imported row
    CSV
    file.rewind

    upload = Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "import.csv")

    post preview_import_csv_path, params: { file: upload }
    preview_token = response.body[/name="preview_token"[^>]*value="([^"]+)"/, 1]

    expect(preview_token).to be_present

    expect do
      post import_csv_path, params: { preview_token: preview_token }
    end.to change(user.budget_months, :count).by(1)
       .and change(ExpenseEntry.where(user: user), :count).by(1)

    expect(response).to redirect_to(budget_months_path)
    expect(flash[:notice]).to include("Import complete: 1 month(s), 1 entry(s).")
  ensure
    file.close
    file.unlink
  end

  it "keeps strict imports all-or-nothing when a row has errors" do
    file = Tempfile.new([ "budget-import-invalid", ".csv" ])
    file.write(<<~CSV)
      Month,Date,Section,Category,Payee,Planned Amount,Actual Amount,Account,Status,Need or Want,Notes
      2026-03,2026-03-02,fixed,Utilities,Pepco,91.22,,Checking,planned,Need,Imported row
      2026-04,2026-04-03,fixed,Utilities,Water,not-money,,Checking,planned,Need,Bad row
    CSV
    file.rewind

    upload = Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "import.csv")

    expect do
      post import_csv_path, params: { file: upload }
    end.not_to change(ExpenseEntry, :count)

    expect(response).to redirect_to(budget_months_path)
    expect(flash[:alert]).to include("Row 3: Planned Amount could not be parsed.")
    expect(user.budget_months.reload).to be_empty
  ensure
    file.close
    file.unlink
  end

  it "surfaces duplicate rows during preview and skips them on import" do
    month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    create(:expense_entry, budget_month: month, user: user, occurred_on: Date.new(2026, 3, 2), section: :fixed, category: "Utilities", payee: "Pepco", planned_amount: 91.22)

    file = Tempfile.new([ "budget-import-duplicate", ".csv" ])
    file.write(<<~CSV)
      Month,Date,Section,Category,Payee,Planned Amount,Actual Amount,Account,Status,Need or Want,Notes
      2026-03,2026-03-02,fixed,Utilities,Pepco,91.22,,Checking,planned,Need,Duplicate row
    CSV
    file.rewind

    upload = Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "import.csv")

    post preview_import_csv_path, params: { file: upload }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("This looks like a duplicate")
    preview_token = response.body[/name="preview_token"[^>]*value="([^"]+)"/, 1]

    expect do
      post import_csv_path, params: { preview_token: preview_token }
    end.not_to change(ExpenseEntry, :count)

    expect(flash[:notice]).to include("1 duplicate row skipped")
  ensure
    file.close
    file.unlink
  end
end
