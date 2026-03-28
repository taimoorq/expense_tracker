require "rails_helper"

RSpec.describe ReleaseCatalog do
  describe ".unread_for" do
    it "returns all releases when the user has never seen one" do
      user = build(:user, last_seen_release_version: nil)

      expect(described_class.unread_for(user).map(&:version)).to eq(%w[0.4.0 0.3.0])
    end

    it "returns only releases newer than the last seen version" do
      user = build(:user, last_seen_release_version: "0.3.0")

      expect(described_class.unread_for(user).map(&:version)).to eq(%w[0.4.0])
    end
  end
end
