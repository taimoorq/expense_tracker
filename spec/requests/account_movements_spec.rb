require "rails_helper"

RSpec.describe "Account movement drilldowns", type: :request do
  let(:user) { create(:user) }
  let(:budget_month) { create(:budget_month, user: user, month_on: Date.new(2026, 4, 1), label: "April 2026") }
  let(:checking) { create(:account, user: user, name: "Checking", kind: :checking) }
  let(:card) { create(:account, user: user, name: "Rewards Visa", kind: :credit_card) }

  before { sign_in user }

  it "shows the entries behind a selected movement total" do
    create(:expense_entry,
      budget_month: budget_month,
      user: user,
      source_account: checking,
      destination_account: card,
      section: :debt,
      status: :paid,
      actual_amount: 300,
      payee: "Rewards Visa")

    create(:expense_entry,
      budget_month: budget_month,
      user: user,
      source_account: card,
      section: :variable,
      status: :paid,
      actual_amount: 42,
      payee: "Coffee Shop")

    get budget_month_account_movement_path(budget_month, account_id: card.id, movement_type: "credit_card_paid")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Credit card payments made")
    expect(response.body).to include("Rewards Visa")
    expect(response.body).to include("$300.00")
    expect(response.body).not_to include("Coffee Shop")
  end

  it "rejects unknown movement types" do
    get budget_month_account_movement_path(budget_month, account_id: card.id, movement_type: "not_real")

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq("Choose a valid account movement to review.")
  end
end
