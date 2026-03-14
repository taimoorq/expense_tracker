require "rails_helper"

RSpec.describe "Admin user access management", type: :request do
  let(:admin_user) { create(:admin_user) }
  let(:user) { create(:user, email: "member@example.com") }

  before do
    sign_in admin_user, scope: :admin_user
  end

  it "requires admin authentication for the admin dashboard" do
    sign_out admin_user

    get admin_root_path

    expect(response).to redirect_to(new_admin_user_session_path)
  end

  it "suspends a user and records an audit log" do
    expect do
      patch suspend_admin_user_path(user), params: { audit_note: "Requested by support" }
    end.to change(AdminAuditLog, :count).by(1)

    expect(response).to redirect_to(admin_user_path(user))
    expect(user.reload.access_state).to eq("suspended")

    audit_log = AdminAuditLog.order(:created_at).last

    expect(audit_log.admin_user).to eq(admin_user)
    expect(audit_log.target_user).to eq(user)
    expect(audit_log.action).to eq("admin.users.suspend")
    expect(audit_log.metadata["note"] || audit_log.metadata[:note]).to eq("Requested by support")
  end

  it "restores a suspended user and records an audit log" do
    user.update!(access_state: :suspended)

    expect do
      patch restore_admin_user_path(user), params: { audit_note: "Access restored after review" }
    end.to change(AdminAuditLog, :count).by(1)

    expect(response).to redirect_to(admin_user_path(user))
    expect(user.reload.access_state).to eq("active")

    audit_log = AdminAuditLog.order(:created_at).last

    expect(audit_log.action).to eq("admin.users.restore")
    expect(audit_log.target_user).to eq(user)
  end
end
