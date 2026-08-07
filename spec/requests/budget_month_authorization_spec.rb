require "rails_helper"

RSpec.describe "Budget month authorization", type: :request do
  it "does not allow a signed in user to access another user's month" do
    signed_in_user = create(:user)
    other_month = create(:budget_month, label: "Private Month")

    sign_in signed_in_user
    get budget_month_path(other_month)

    expect(response).to have_http_status(:not_found)
  end

  it "renders only the entries matching a valid review reason" do
    user = create(:user)
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month)
    create(:expense_entry, user: user, budget_month: month, occurred_on: Date.current, status: :planned, payee: "Due utility", category: "Utilities")
    create(:expense_entry, user: user, budget_month: month, occurred_on: Date.current + 5.days, status: :planned, payee: "Future utility", category: "Utilities")

    sign_in user
    get budget_month_tab_path(month, "entries", review: "due")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Review mode")
    expect(response.body).to include("Due utility")
    expect(response.body).not_to include("Future utility")
    expect(response.body).to include('aria-current="true"')
  end

  it "ignores unsupported review reasons without exposing review results" do
    user = create(:user)
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))
    create(:expense_entry, user: user, budget_month: month, occurred_on: Date.current, status: :planned, payee: "Private item")

    sign_in user
    get budget_month_tab_path(month, "entries", review: "not-a-review")

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Review mode")
    expect(response.body).not_to include("Private item")
  end

  it "does not mutate due recurring entries while rendering month pages" do
    user = create(:user)
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month)
    due_entry = create(
      :expense_entry,
      user: user,
      budget_month: month,
      occurred_on: Date.current,
      planned_amount: 89.50,
      actual_amount: nil,
      status: :planned,
      source_file: "subscription"
    )

    sign_in user

    expect { get budget_months_path }
      .not_to change { due_entry.reload.slice(:status, :actual_amount, :auto_completed_at, :updated_at) }
    expect(response).to have_http_status(:ok)

    expect { get budget_month_tab_path(month, "timeline") }
      .not_to change { due_entry.reload.slice(:status, :actual_amount, :auto_completed_at, :updated_at) }
    expect(response).to have_http_status(:ok)
  end

  it "renders only the requested month ledger mode" do
    user = create(:user)
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month)
    create(:expense_entry, user: user, budget_month: month, payee: "Mode-specific entry")

    sign_in user

    get budget_month_tab_path(month, "timeline")
    expect(response.body).to include('data-panel-name="full-list"')
    expect(response.body).not_to include('data-panel-name="sections"')
    expect(response.body).not_to include('data-panel-name="calendar"')
    expect(response.body).not_to include('id="mobile_expense_entry_')

    get budget_month_tab_path(month, "timeline", view: "sections")
    expect(response.body).to include('data-panel-name="sections"')
    expect(response.body).not_to include('data-panel-name="full-list"')
    expect(response.body).not_to include('data-panel-name="calendar"')

    get budget_month_tab_path(month, "calendar")
    expect(response.body).to include('data-panel-name="calendar"')
    expect(response.body).not_to include('data-panel-name="sections"')
    expect(response.body).not_to include('data-panel-name="full-list"')
  end
end
