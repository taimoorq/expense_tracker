require "rails_helper"

RSpec.describe "Manual Activity", type: :system, js: true do
  it "records a transfer through the focused form and keeps account import selection explicit" do
    user = create(:user, last_seen_release_version: Platform::ReleaseCatalog.latest.version)
    workspace = Identity::NewWorkspaceSetup.call(user: user)
    create(:account, user: user, budget_workspace: workspace, name: "Everyday checking")
    create(:account, user: user, budget_workspace: workspace, name: "Rainy day savings", kind: :savings)
    sign_in_as(user)
    visit activity_path(view: "all")
    click_link "Record transaction"
    expect(page).not_to have_select("Money goes to (transfers only)")
    select "Transfer between accounts", from: "Money movement"
    select "Everyday checking", from: "Activity account (money leaves this account for a transfer)"
    select "Rainy day savings", from: "Money goes to (transfers only)"
    fill_in "Description", with: "Monthly savings"
    fill_in "Amount", with: "75.25"
    click_button "Record transaction"
    expect(page).to have_content("Transaction recorded.")
    expect(page).to have_content("Monthly savings")
    expect(workspace.financial_transactions.sole.account_postings.order(:sequence_number).pluck(:amount)).to eq([ -75.25.to_d, 75.25.to_d ])
    click_link "Import activity"
    expect(page).to have_select("Account", selected: "Everyday checking")
    select "Rainy day savings", from: "Account"
    click_button "Choose statement file"
    expect(page).to have_content("Rainy day savings")
    expect(page).to have_field("Institution CSV export")
  end
end
