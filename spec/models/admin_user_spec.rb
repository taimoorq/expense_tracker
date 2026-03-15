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
end
