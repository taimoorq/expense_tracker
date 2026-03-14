require "rails_helper"

RSpec.describe AdminBootstrapper, type: :service do
  describe "#call" do
    it "skips when no admin environment values are present" do
      result = described_class.new(email: "", password: "").call

      expect(result.status).to eq("skipped")
      expect(result.admin_user).to be_nil
    end

    it "creates an admin when both values are provided" do
      expect do
        result = described_class.new(email: "admin@example.com", password: "password123!").call

        expect(result.status).to eq("created")
        expect(result.admin_user.email).to eq("admin@example.com")
      end.to change(AdminUser, :count).by(1)
    end

    it "updates an existing admin password when it changes" do
      admin_user = create(:admin_user, email: "admin@example.com", password: "old-password", password_confirmation: "old-password")

      result = described_class.new(email: admin_user.email, password: "new-password123!").call

      expect(result.status).to eq("updated")
      expect(admin_user.reload.valid_password?("new-password123!")).to be(true)
    end

    it "raises when only one admin bootstrap value is provided" do
      expect do
        described_class.new(email: "admin@example.com", password: "").call
      end.to raise_error(
        ArgumentError,
        "ADMIN_USER_EMAIL and ADMIN_USER_PASSWORD must both be provided to bootstrap an admin user"
      )
    end
  end
end
