require "rails_helper"

RSpec.describe ReleaseCatalog do
  describe ".current_version" do
    it "uses the newest release entry as the app version" do
      expect(described_class.current_version).to eq("2.0.0")
    end
  end

  describe ".unread_for" do
    it "returns all releases when the user has never seen one" do
      user = build(:user, last_seen_release_version: nil)

      expect(described_class.unread_for(user).map(&:version)).to eq(described_class.releases.map(&:version))
    end

    it "returns only releases newer than the last seen version" do
      seen_release = described_class.releases.last
      user = build(:user, last_seen_release_version: seen_release.version)

      expect(described_class.unread_for(user).map(&:version)).to eq(described_class.releases[0...-1].map(&:version))
    end

    it "alerts users on 1.2.0 about the 2.0 workspace release" do
      user = build(:user, last_seen_release_version: "1.2.0")

      expect(described_class.latest_unread_for(user)&.version).to eq("2.0.0")
      expect(described_class.latest_unread_for(user)&.title).to eq("One financial workspace, end to end")
    end
  end
end
