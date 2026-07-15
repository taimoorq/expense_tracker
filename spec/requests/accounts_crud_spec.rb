require "rails_helper"

RSpec.describe "Accounts CRUD", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "shows one top-level heading and resolved imported balances on the accounts overview" do
    checking = create(:account, user: user, name: "Checking", kind: :checking, include_in_net_worth: true)
    create(:account_snapshot, account: checking, recorded_on: Date.new(2026, 7, 1), balance: 1_000)
    import = create(
      :account_activity_import,
      account: checking,
      metadata: {
        institution_balance: "2200.00",
        institution_balance_as_of: "2026-07-02"
      }
    )
    create(:account_activity, account_activity_import: import, account: checking, transaction_on: Date.new(2026, 7, 3), amount: 25, account_delta: -25)

    get accounts_path

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.css(".ta-content-header h1").text.strip).to eq("Accounts")
    expect(document.css("nav[aria-label='Breadcrumb']")).to be_empty
    expect(response.body).to include("$2,175.00")
    expect(response.body).to include("Institution import")
    expect(response.body).to include("Latest trusted source")
  end

  it "does not show imported activity as a balance without a trusted source" do
    card = create(:account, user: user, name: "Store Card", kind: :credit_card, include_in_net_worth: true)
    import = create(:account_activity_import, account: card)
    create(:account_activity, account_activity_import: import, account: card, transaction_on: Date.new(2026, 7, 3), amount: 650, account_delta: -650)

    get accounts_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Needs source")
    expect(response.body).to include("Imported rows need a balance source")
    expect(response.body).not_to include("$650.00")
  end

  it "shows period source labels on the account detail page" do
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    create(:account_snapshot, account: checking, recorded_on: Date.new(2026, 6, 30), balance: 1_000)
    import = create(:account_activity_import, account: checking)
    create(:account_activity, account_activity_import: import, account: checking, transaction_on: Date.new(2026, 7, 3), amount: 25, account_delta: -25)

    get account_path(checking)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Imported activity")
    expect(response.body).to include("Activity through")
    expect(response.body).to include("1 imported row")
  end

  it "renders account-specific overview stories and server-addressable account paths" do
    card = create(:account, user: user, name: "Rewards Card", kind: :credit_card)
    create(:account_snapshot, account: card, recorded_on: Date.new(2026, 7, 1), balance: -500)

    get account_path(card, view: "overview", range: "12m")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Am I adding debt faster than I am paying it down?")
    expect(response.body).to include("Charges and payments over time")
    expect(response.body).to include("Payments &amp; credits")
    expect(response.body).to include("Current Debt")
    expect(response.body).to include('aria-label="Account information"')
    expect(response.body).to include('aria-current="page"')

    get account_path(card, view: "manage")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Monthly balance history")
    expect(response.body).to include("How balance is calculated")
    expect(response.body).to include("Record balance")
  end

  it "keeps institution and budget-linked activity separate in exact drilldowns" do
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 7, 1), label: "July 2026")
    activity_import = create(:account_activity_import, account: checking)
    create(:account_activity, account: checking, account_activity_import: activity_import, transaction_on: Date.new(2026, 7, 3), description: "CARD PURCHASE", amount: 25, account_delta: -25)
    create(:expense_entry, user: user, budget_month: month, source_account: checking, occurred_on: Date.new(2026, 7, 4), payee: "Budget Payee", section: :fixed, status: :paid, actual_amount: 40)

    get account_path(
      checking,
      view: "activity",
      source: "institution_activity",
      direction: "outgoing",
      starts_on: "2026-07-01",
      ends_on: "2026-07-31"
    )

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Institution activity")
    expect(response.body).to include("CARD PURCHASE")
    expect(response.body).not_to include("Budget Payee")
    expect(response.body).to include("Clear filters")

    get account_path(checking, view: "activity", source: "budget_entries")

    expect(response.body).to include("Budget-linked activity")
    expect(response.body).to include("Budget Payee")
    expect(response.body).not_to include("CARD PURCHASE")
  end

  it "falls back to the overview for unknown account views and ranges" do
    savings = create(:account, user: user, kind: :savings)

    get account_path(savings, view: "unknown", range: "forever")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Is this balance growing, and how often am I drawing from it?")
    expect(response.body).to include("Deposits and withdrawals over time")
  end

  it "renders the shared overview contract for every account kind without overstating tracked assets" do
    Account.kinds.each_key do |kind|
      account = create(:account, user: user, kind: kind, name: "#{kind.humanize} #{SecureRandom.hex(2)}")

      get account_path(account)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("What This View Answers")
      expect(response.body).to include("Period and source")
    end

    tracked_asset = create(:account, user: user, kind: :brokerage, name: "Tracked Brokerage")
    create(:account_snapshot, account: tracked_asset, balance: 10_000, recorded_on: Date.current)

    get account_path(tracked_asset)

    expect(response.body).to include("This is tracked value, not investment performance.")
    expect(response.body).not_to include("Investment return")
  end

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

  it "does not expose another user's account views or activity drilldowns" do
    other_account = create(:account)

    get account_path(other_account, view: "activity", source: "institution_activity")

    expect(response).to have_http_status(:not_found)
  end
end
