require "rails_helper"

RSpec.describe "Admin finance boundary", type: :request do
  let(:admin_user) { create(:admin_user) }
  let(:user) { create(:user) }
  let!(:budget_month) { create(:budget_month, user: user) }
  let!(:account) { create(:account, user: user) }

  before do
    sign_in admin_user, scope: :admin_user
  end

  it "does not allow an admin to reach the user dashboard" do
    get root_path

    expect(response).to redirect_to(new_user_session_path)
  end

  it "does not allow an admin to reach budget month pages" do
    get budget_month_path(budget_month)

    expect(response).to redirect_to(new_user_session_path)
  end

  it "does not allow an admin to reach accounts and net worth pages" do
    get accounts_path

    expect(response).to redirect_to(new_user_session_path)
  end

  it "does not allow an admin to reach planning templates" do
    get planning_templates_path

    expect(response).to redirect_to(new_user_session_path)
  end
end
