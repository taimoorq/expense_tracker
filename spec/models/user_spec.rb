require "rails_helper"

RSpec.describe User, type: :model do
  it "blocks authentication when access is suspended" do
    user = build(:user, access_state: :suspended)

    expect(user.active_for_authentication?).to be(false)
    expect(user.inactive_message).to eq(:suspended)
  end
end
