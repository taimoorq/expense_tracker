require "rails_helper"

RSpec.describe "Backup & restore", type: :system do
  it "is available as a top-level navigation link" do
    user = create(:user, email: "backup@example.com")

    sign_in_as(user)
    visit root_path

    find("a[title='Backup & Restore']").click

    expect(page).to have_current_path(backup_restore_path, ignore_query: false)
    expect(page).to have_content("Backup & Restore")
    expect(page).to have_content("Export Data")
    expect(page).to have_content("Import Backup")
    expect(page).to have_link("Download sample backup")
    expect(page).to have_content("This sample is for structure reference")
  end

  it "shows an import preview for an encrypted backup before restore" do
    user = create(:user, email: "backuppreview@example.com")

    payload = {
      format: UserDataExport::FORMAT_NAME,
      version: UserDataExport::FORMAT_VERSION,
      exported_at: Time.current.iso8601,
      scopes: [ "planning_templates", "accounts" ],
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
        accounts: [
          {
            name: "Imported Checking",
            institution_name: "Bank",
            kind: "checking",
            active: true,
            include_in_net_worth: true,
            include_in_cash: true,
            notes: nil,
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
    }
    file = Tempfile.new([ "expense-tracker-backup", ".json" ])
    file.write(UserDataBackupCodec.encode(payload: payload, password: "very-secret"))
    file.rewind

    sign_in_as(user)
    visit backup_restore_path

    attach_file "Backup File", file.path
    fill_in "Backup password", with: "very-secret"
    uncheck "Restore Months"
    click_button "Preview Import"

    expect(page).to have_content("Import Preview")
    expect(page).to have_content("Encrypted backup")
    expect(page).to have_content("1 template will replace the current template library")
    expect(page).to have_content("1 account and 1 snapshot will be restored")
    expect(page).to have_button("Restore Selected Data")
  ensure
    file.close
    file.unlink
  end

  it "requires confirmation before restoring a sample backup" do
    user = create(:user, email: "samplebackup@example.com")
    file = Tempfile.new([ "expense-tracker-sample-backup", ".json" ])
    file.write(UserDataSampleBackup.new.to_json)
    file.rewind

    sign_in_as(user)
    visit backup_restore_path

    attach_file "Backup File", file.path
    uncheck "Restore Months"
    uncheck "Restore Accounts"
    click_button "Preview Import"

    expect(page).to have_content("Reference-only sample backup")
    expect(page).to have_unchecked_field("confirm_sample_backup")

    click_button "Restore Selected Data"

    expect(page).to have_content("Confirm that you want to import the reference-only sample backup")

    check "confirm_sample_backup"
    click_button "Restore Selected Data"

    expect(page).to have_content("Import complete")
    expect(page).to have_content("Import complete: restored 5 planning templates.")
  ensure
    file.close
    file.unlink
  end
end
