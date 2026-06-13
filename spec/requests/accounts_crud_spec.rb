require "rails_helper"

RSpec.describe "Accounts CRUD", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "creates an account with an initial snapshot" do
    expect do
      post accounts_path, params: {
        account: {
          name: "Emergency Savings",
          institution_name: "Ally",
          kind: "savings",
          include_in_net_worth: "1",
          include_in_cash: "1",
          active: "1",
          notes: "Rainy day fund",
          initial_snapshot: {
            recorded_on: "2026-03-14",
            balance: "8500.25",
            available_balance: "8500.25",
            notes: "Opening balance"
          }
        }
      }
    end.to change(Account, :count).by(1).and change(AccountSnapshot, :count).by(1)

    account = user.accounts.find_by!(name: "Emergency Savings")

    expect(response).to redirect_to(account_path(account))
    expect(flash[:notice]).to eq("Account created and initial balance recorded.")
    expect(account.account_snapshots.first.balance.to_d).to eq(8500.25.to_d)
  end

  it "creates an account without an initial snapshot when snapshot fields are blank" do
    expect do
      post accounts_path, params: {
        account: {
          name: "Travel Savings",
          institution_name: "Ally",
          kind: "savings",
          include_in_net_worth: "1",
          include_in_cash: "0",
          active: "1",
          notes: "Vacations",
          initial_snapshot: {
            recorded_on: "",
            balance: "",
            available_balance: "",
            notes: ""
          }
        }
      }
    end.to change(Account, :count).by(1)
      .and change(AccountSnapshot, :count).by(0)

    account = user.accounts.find_by!(name: "Travel Savings")

    expect(response).to redirect_to(account_path(account))
    expect(flash[:notice]).to eq("Account created. Add a balance snapshot to start tracking it.")
  end

  it "creates a credit card account with a monthly payment schedule" do
    checking = create(:account, user: user, name: "Checking", kind: :checking)

    expect do
      post accounts_path, params: {
        account: {
          name: "Visa Rewards",
          institution_name: "Chase",
          kind: "credit_card",
          include_in_net_worth: "1",
          include_in_cash: "0",
          active: "1",
          credit_card_payment_schedule: {
            enabled: "1",
            payment_account_id: checking.id,
            minimum_payment: "75.00",
            due_day: "18",
            priority: "2",
            active: "1",
            notes: "Monthly autopay"
          }
        }
      }
    end.to change(Account, :count).by(1).and change(CreditCard, :count).by(1)

    account = user.accounts.find_by!(name: "Visa Rewards")
    schedule = user.credit_cards.find_by!(name: "Visa Rewards")

    expect(response).to redirect_to(account_path(account))
    expect(flash[:notice]).to eq("Account created and card payment scheduled. Add a balance snapshot when you are ready.")
    expect(schedule.linked_account).to eq(account)
    expect(schedule.payment_account).to eq(checking)
    expect(schedule.account).to eq("Checking")
    expect(schedule.minimum_payment.to_d).to eq(75.to_d)
  end

  it "does not create a partial account when requested card payment schedule details are invalid" do
    checking = create(:account, user: user, name: "Checking", kind: :checking)

    expect do
      post accounts_path, params: {
        account: {
          name: "Store Card",
          kind: "credit_card",
          include_in_net_worth: "1",
          include_in_cash: "0",
          active: "1",
          credit_card_payment_schedule: {
            enabled: "1",
            payment_account_id: checking.id,
            minimum_payment: "",
            due_day: "12",
            priority: "1",
            active: "1"
          }
        }
      }
    end.to change(Account, :count).by(0).and change(CreditCard, :count).by(0)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Fix the card payment details.")
  end

  it "updates an owned account" do
    account = create(:account, user: user, name: "Checking")

    patch account_path(account), params: {
      account: {
        institution_name: "Chase",
        include_in_cash: "1",
        notes: "Daily spending"
      }
    }

    expect(response).to redirect_to(account_path(account))
    expect(flash[:notice]).to eq("Account updated.")
    expect(account.reload.institution_name).to eq("Chase")
    expect(account.include_in_cash).to be(true)
  end

  it "does not allow updating another user's account" do
    other_account = create(:account)

    patch account_path(other_account), params: { account: { notes: "nope" } }

    expect(response).to have_http_status(:not_found)
    expect(other_account.reload.notes).not_to eq("nope")
  end
end
