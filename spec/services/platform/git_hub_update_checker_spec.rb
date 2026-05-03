require "rails_helper"

RSpec.describe Platform::GitHubUpdateChecker do
  around do |example|
    original_env = {
      "GITHUB_UPDATE_CHECKS_ENABLED" => ENV["GITHUB_UPDATE_CHECKS_ENABLED"],
      "GITHUB_UPDATE_REPOSITORY" => ENV["GITHUB_UPDATE_REPOSITORY"],
      "GITHUB_UPDATE_README_URL" => ENV["GITHUB_UPDATE_README_URL"]
    }

    original_env.each_key { |key| ENV.delete(key) }
    example.run
  ensure
    original_env.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  describe ".available_update" do
    it "returns the GitHub release when it is newer than the local app release" do
      release = described_class::Release.new(
        version: "999.0.0",
        tag_name: "v999.0.0",
        name: "Future release",
        html_url: "https://github.com/taimoorq/expense_tracker/releases/tag/v999.0.0"
      )

      allow(described_class).to receive(:latest_release).and_return(release)

      expect(described_class.available_update).to eq(release)
    end

    it "does not return a GitHub release when the local app release is current" do
      release = described_class::Release.new(
        version: Platform::ReleaseCatalog.current_version,
        tag_name: "v#{Platform::ReleaseCatalog.current_version}"
      )

      allow(described_class).to receive(:latest_release).and_return(release)

      expect(described_class.available_update).to be_nil
    end
  end

  describe ".latest_release" do
    it "fetches and normalizes the latest GitHub release metadata" do
      ENV["GITHUB_UPDATE_CHECKS_ENABLED"] = "true"
      response = instance_double(
        Net::HTTPResponse,
        code: "200",
        body: JSON.generate(
          "tag_name" => "v1.2.3",
          "name" => "A tidy release",
          "html_url" => "https://github.com/taimoorq/expense_tracker/releases/tag/v1.2.3",
          "published_at" => "2026-05-03T12:00:00Z"
        )
      )
      http_client = instance_double(Net::HTTP)

      allow(http_client).to receive(:use_ssl=)
      allow(http_client).to receive(:open_timeout=)
      allow(http_client).to receive(:read_timeout=)
      allow(http_client).to receive(:request).and_return(response)
      allow(Net::HTTP).to receive(:new).with("api.github.com", 443).and_return(http_client)

      release = described_class.latest_release

      expect(release.version).to eq("1.2.3")
      expect(release.label).to eq("v1.2.3")
      expect(release.html_url).to eq("https://github.com/taimoorq/expense_tracker/releases/tag/v1.2.3")
    end
  end

  describe ".enabled?" do
    it "is disabled by default in tests" do
      expect(described_class.enabled?).to be(false)
    end

    it "can be enabled through the environment" do
      ENV["GITHUB_UPDATE_CHECKS_ENABLED"] = "true"

      expect(described_class.enabled?).to be(true)
    end
  end

  describe ".readme_update_url" do
    it "points at the update section in the configured repository README" do
      ENV["GITHUB_UPDATE_REPOSITORY"] = "example/budget_app"

      expect(described_class.readme_update_url).to eq("https://github.com/example/budget_app#updating-a-self-hosted-install")
    end

    it "allows an explicit README URL override" do
      ENV["GITHUB_UPDATE_README_URL"] = "https://example.com/update"

      expect(described_class.readme_update_url).to eq("https://example.com/update")
    end
  end
end
