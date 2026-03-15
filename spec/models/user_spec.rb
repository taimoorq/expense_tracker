require "rails_helper"

RSpec.describe User, type: :model do
  it "blocks authentication when access is suspended" do
    user = build(:user, access_state: :suspended)

    expect(user.active_for_authentication?).to be(false)
    expect(user.inactive_message).to eq(:suspended)
  end

  it "locks access after the configured number of failed authentication attempts" do
    user = create(:user)

    Devise.maximum_attempts.times do
      expect(user.valid_for_authentication? { false }).to be(false)
    end

    user.reload

    expect(user.failed_attempts).to eq(Devise.maximum_attempts)
    expect(user.access_locked?).to be(true)
    expect(user.locked_at).to be_present
  end
end
