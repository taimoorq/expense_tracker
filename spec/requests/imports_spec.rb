require "rails_helper"

RSpec.describe "CSV imports", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "imports rows into the signed in user's months only" do
    file = Tempfile.new(["budget-import", ".csv"])
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

    expect(response).to redirect_to(root_path)
    expect(flash[:notice]).to include("Import complete")
    expect(BudgetMonth.last.user).to eq(user)
  ensure
    file.close
    file.unlink
  end
end