require "rails_helper"

RSpec.describe AdminUser, type: :model do
  it "locks access after the configured number of failed authentication attempts" do
    admin_user = create(:admin_user)

    Devise.maximum_attempts.times do
      expect(admin_user.valid_for_authentication? { false }).to be(false)
    end

    admin_user.reload

    expect(admin_user.failed_attempts).to eq(Devise.maximum_attempts)
    expect(admin_user.access_locked?).to be(true)
    expect(admin_user.locked_at).to be_present
  end

  it "retains administrator identity referenced by audit evidence" do
    admin_user = create(:admin_user)
    AdminAuditLog.create!(admin_user: admin_user, action: "user.suspended")

    expect(admin_user.destroy).to be(false)
    expect(admin_user.errors[:base]).to include("Cannot delete record because dependent admin audit logs exist")
    expect(admin_user.reload).to be_persisted
  end
end
