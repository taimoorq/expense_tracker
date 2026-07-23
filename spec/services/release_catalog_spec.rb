require "rails_helper"

RSpec.describe ReleaseCatalog do
  describe ".current_version" do
    it "uses the newest release entry as the app version" do
      expect(described_class.current_version).to eq("0.10.0")
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
  end
end
