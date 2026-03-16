require "rails_helper"

RSpec.describe "Backup & restore", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "exports the selected scopes as versioned JSON" do
    create(:pay_schedule, user: user, name: "Acme Payroll")
    account = create(:account, user: user, name: "Checking")
    create(:account_snapshot, account: account, recorded_on: Date.new(2026, 3, 15), balance: 2400)
    create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")

    post export_backup_restore_path, params: { export_scopes: [ "planning_templates", "accounts" ] }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    expect(response.headers["Content-Disposition"]).to include("expense-tracker-backup-")

    payload = JSON.parse(response.body)

    expect(payload.fetch("format")).to eq("expense_tracker_backup")
    expect(payload.fetch("version")).to eq(1)
    expect(payload.fetch("scopes")).to contain_exactly("planning_templates", "accounts")
    expect(payload.fetch("data")).to have_key("planning_templates")
    expect(payload.fetch("data")).to have_key("accounts")
    expect(payload.fetch("data")).not_to have_key("budget_months")
  end

  it "exports budget_months and expense_entries without removed fields" do
    month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    create(:expense_entry, budget_month: month, user: user, payee: "Rent", category: "Housing", section: :fixed, status: :planned, planned_amount: 1200)

    post export_backup_restore_path, params: { export_scopes: [ "budget_months" ] }

    expect(response).to have_http_status(:ok)
    payload = JSON.parse(response.body)
    months = payload.dig("data", "budget_months")
    expect(months.size).to eq(1)
    month_data = months.first
    expect(month_data).to have_key("label")
    expect(month_data).to have_key("month_on")
    expect(month_data).to have_key("leftover")
    expect(month_data).to have_key("notes")
    expect(month_data).not_to have_key("planned_income")
    expect(month_data).not_to have_key("actual_income")
    expect(month_data["expense_entries"].first).to include("payee" => "Rent")
  end

  it "exports an encrypted backup when a password is provided" do
    create(:pay_schedule, user: user, name: "Acme Payroll")

    post export_backup_restore_path, params: { export_scopes: [ "planning_templates" ], export_password: "very-secret" }

    expect(response).to have_http_status(:ok)

    payload = JSON.parse(response.body)
    expect(payload.fetch("format")).to eq("expense_tracker_backup_encrypted")

    decoded = UserDataBackupCodec.decode(source: response.body, password: "very-secret")

    expect(decoded[:success]).to be(true)
    expect(decoded[:encrypted]).to be(true)
    expect(decoded[:payload].fetch(:data)).to have_key(:planning_templates)
  end

  it "downloads a sample backup file with the supported structure" do
    get sample_backup_restore_path

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    expect(response.headers["Content-Disposition"]).to include("expense-tracker-sample-backup.json")

    payload = JSON.parse(response.body)

    expect(payload.fetch("format")).to eq("expense_tracker_backup")
    expect(payload.fetch("version")).to eq(1)
    expect(payload.fetch("sample_backup")).to be(true)
    expect(payload.fetch("sample_notice")).to include("Reference-only sample backup")
    expect(payload.fetch("scopes")).to contain_exactly("planning_templates", "budget_months", "accounts")
    expect(payload.dig("data", "planning_templates", "pay_schedules")).not_to be_empty
    expect(payload.dig("data", "budget_months", 0, "expense_entries")).not_to be_empty
    expect(payload.dig("data", "accounts", 0, "account_snapshots")).not_to be_empty
  end

  it "imports budget_months from backups with legacy planned_income/actual_income (ignored)" do
    file = Tempfile.new([ "expense-tracker-backup", ".json" ])
    file.write(
      JSON.pretty_generate(
        format: "expense_tracker_backup",
        version: 1,
        exported_at: Time.current.iso8601,
        scopes: [ "budget_months" ],
        data: {
          budget_months: [
            {
              label: "Legacy March 2026",
              month_on: "2026-03-01",
              planned_income: "5000.0",
              actual_income: "4980.0",
              leftover: nil,
              notes: "Old backup format",
              expense_entries: [
                {
                  occurred_on: "2026-03-02",
                  section: "fixed",
                  category: "Utilities",
                  payee: "Pepco",
                  planned_amount: "91.22",
                  actual_amount: nil,
                  account: "Checking",
                  status: "planned",
                  need_or_want: "Need",
                  notes: nil,
                  source_file: "manual"
                }
              ]
            }
          ]
        }
      )
    )
    file.rewind

    upload = Rack::Test::UploadedFile.new(file.path, "application/json", original_filename: "legacy-backup.json")
    post preview_backup_restore_path, params: { file: upload, import_scopes: [ "budget_months" ] }
    preview_token = response.body[/name="preview_token"[^>]*value="([^"]+)"/, 1]

    post import_backup_restore_path, params: { preview_token: preview_token }
    follow_redirect!

    expect(response).to have_http_status(:ok)
    expect(user.budget_months.reload.pluck(:label)).to eq([ "Legacy March 2026" ])
    expect(user.expense_entries.reload.pluck(:payee)).to eq([ "Pepco" ])
  ensure
    file.close
    file.unlink
  end

  it "imports selected scopes from a backup file and replaces existing data" do
    create(:pay_schedule, user: user, name: "Old Payroll")
    create(:budget_month, user: user, month_on: Date.new(2026, 4, 1), label: "April 2026")
    create(:account, user: user, name: "Old Checking")

    file = Tempfile.new([ "expense-tracker-backup", ".json" ])
    file.write(
      JSON.pretty_generate(
        format: "expense_tracker_backup",
        version: 1,
        exported_at: Time.current.iso8601,
        scopes: [ "planning_templates", "budget_months", "accounts" ],
        data: {
          planning_templates: {
            pay_schedules: [
              {
                name: "Imported Payroll",
                cadence: "monthly",
                amount: "3200.0",
                first_pay_on: "2026-01-15",
                day_of_month_one: 15,
                day_of_month_two: nil,
                weekend_adjustment: "no_adjustment",
                account: "Checking",
                active: true
              }
            ],
            subscriptions: [],
            monthly_bills: [],
            payment_plans: [],
            credit_cards: []
          },
          budget_months: [
            {
              label: "March 2026",
              month_on: "2026-03-01",
              leftover: nil,
              notes: "Imported month",
              expense_entries: [
                {
                  occurred_on: "2026-03-02",
                  section: "fixed",
                  category: "Utilities",
                  payee: "Pepco",
                  planned_amount: "91.22",
                  actual_amount: nil,
                  account: "Checking",
                  status: "planned",
                  need_or_want: "Need",
                  notes: "Imported entry",
                  source_file: "manual"
                }
              ]
            }
          ],
          accounts: [
            {
              name: "Imported Checking",
              institution_name: "Bank",
              kind: "checking",
              active: true,
              include_in_net_worth: true,
              include_in_cash: true,
              notes: "Imported account",
              account_snapshots: [
                {
                  recorded_on: "2026-03-15",
                  balance: "2400.0",
                  available_balance: "2300.0",
                  notes: "Imported snapshot"
                }
              ]
            }
          ]
        }
      )
    )
    file.rewind

    upload = Rack::Test::UploadedFile.new(file.path, "application/json", original_filename: "backup.json")

    post preview_backup_restore_path, params: { file: upload, import_scopes: [ "planning_templates", "budget_months", "accounts" ] }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Import Preview")

    preview_token = response.body[/name="preview_token"[^>]*value="([^"]+)"/, 1]
    expect(preview_token).to be_present

    post import_backup_restore_path, params: { preview_token: preview_token }
    follow_redirect!

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Import complete")
    expect(user.pay_schedules.reload.pluck(:name)).to eq([ "Imported Payroll" ])
    expect(user.budget_months.reload.pluck(:label)).to eq([ "March 2026" ])
    expect(user.expense_entries.reload.pluck(:payee)).to eq([ "Pepco" ])
    expect(user.accounts.reload.pluck(:name)).to eq([ "Imported Checking" ])
    expect(user.account_snapshots.reload.pluck(:notes)).to eq([ "Imported snapshot" ])
  ensure
    file.close
    file.unlink
  end

  it "requires explicit confirmation before importing a sample backup" do
    file = Tempfile.new([ "expense-tracker-sample-backup", ".json" ])
    file.write(UserDataSampleBackup.new.to_json)
    file.rewind

    upload = Rack::Test::UploadedFile.new(file.path, "application/json", original_filename: "sample-backup.json")

    post preview_backup_restore_path, params: { file: upload, import_scopes: [ "planning_templates" ] }

    preview_token = response.body[/name="preview_token"[^>]*value="([^"]+)"/, 1]
    expect(preview_token).to be_present

    expect do
      post import_backup_restore_path, params: { preview_token: preview_token }
    end.not_to change { user.pay_schedules.count }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Confirm that you want to import the reference-only sample backup")

    expect do
      post import_backup_restore_path, params: { preview_token: preview_token, confirm_sample_backup: "1" }
      follow_redirect!
    end.to change { user.pay_schedules.count }.by(1)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Import complete")
  ensure
    file.close
    file.unlink
  end

  it "previews and imports an encrypted backup with the password" do
    payload = UserDataExport.new(user: user, scopes: [ "planning_templates" ]).as_json
    encrypted_json = UserDataBackupCodec.encode(payload: payload, password: "very-secret")

    file = Tempfile.new([ "expense-tracker-backup", ".json" ])
    file.write(encrypted_json)
    file.rewind

    upload = Rack::Test::UploadedFile.new(file.path, "application/json", original_filename: "backup-encrypted.json")

    post preview_backup_restore_path, params: { file: upload, import_scopes: [ "planning_templates" ], import_password: "very-secret" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Encrypted backup")
  ensure
    file.close
    file.unlink
  end
end
