require "rails_helper"

RSpec.describe "db/seeds" do
  def load_seed
    Rails.application.load_seed
  end

  around do |example|
    original_mode = ENV["SEED_MODE"]
    original_email = ENV["SEED_USER_EMAIL"]
    original_password = ENV["SEED_USER_PASSWORD"]
    original_admin_email = ENV["ADMIN_USER_EMAIL"]
    original_admin_password = ENV["ADMIN_USER_PASSWORD"]

    ENV["SEED_MODE"] = seed_mode
    ENV["SEED_USER_EMAIL"] = seed_email
    ENV["SEED_USER_PASSWORD"] = seed_password
    ENV["ADMIN_USER_EMAIL"] = admin_seed_email
    ENV["ADMIN_USER_PASSWORD"] = admin_seed_password

    example.run
  ensure
    ENV["SEED_MODE"] = original_mode
    ENV["SEED_USER_EMAIL"] = original_email
    ENV["SEED_USER_PASSWORD"] = original_password
    ENV["ADMIN_USER_EMAIL"] = original_admin_email
    ENV["ADMIN_USER_PASSWORD"] = original_admin_password
  end

  let(:seed_password) { "password123!" }
  let(:admin_seed_email) { nil }
  let(:admin_seed_password) { nil }

  context "when seeding users only" do
    let(:seed_mode) { "users" }
    let(:seed_email) { "users-only@example.com" }

    it "creates the user without related demo data" do
      expect { load_seed }.to change(User, :count).by(1)

      user = User.find_by!(email: seed_email)

      expect(user.valid_password?(seed_password)).to be(true)
      expect(user.budget_months).to be_empty
      expect(user.expense_entries).to be_empty
      expect(user.pay_schedules).to be_empty
      expect(user.subscriptions).to be_empty
      expect(user.monthly_bills).to be_empty
      expect(user.payment_plans).to be_empty
      expect(user.credit_cards).to be_empty
      expect(user.accounts).to be_empty
      expect(user.account_snapshots).to be_empty
      expect(AdminUser.count).to eq(0)
    end
  end

  context "when admin seed credentials are provided" do
    let(:seed_mode) { "users" }
    let(:seed_email) { "with-admin@example.com" }
    let(:admin_seed_email) { "admin@example.com" }
    let(:admin_seed_password) { "password123!" }

    it "creates or updates the admin user during seeding" do
      expect { load_seed }.to change(User, :count).by(1).and change(AdminUser, :count).by(1)

      admin_user = AdminUser.find_by!(email: admin_seed_email)

      expect(admin_user.valid_password?(admin_seed_password)).to be(true)
    end
  end

  context "when seeding users with transactions" do
    let(:seed_mode) { "users_with_transactions" }
    let(:seed_email) { "users-with-transactions@example.com" }

    it "creates the user and demo data" do
      expect { load_seed }.to change(User, :count).by(1)

      user = User.find_by!(email: seed_email)

      expect(user.valid_password?(seed_password)).to be(true)
      expect(user.budget_months).not_to be_empty
      expect(user.expense_entries).not_to be_empty
      expect(user.pay_schedules.count).to eq(1)
      expect(user.subscriptions.count).to eq(3)
      expect(user.monthly_bills.count).to eq(2)
      expect(user.payment_plans.count).to eq(1)
      expect(user.credit_cards.count).to eq(2)
      expect(user.accounts.count).to eq(4)
      expect(user.account_snapshots.count).to eq(12)
      expect(user.accounts.find_by!(name: "Rewards Visa Balance").latest_balance.to_d).to eq((-412.38).to_d)
      expect(user.accounts.find_by!(name: "Emergency Savings").account_snapshots.count).to eq(3)
    end

    it "can switch the same user back to users-only mode" do
      load_seed

      ENV["SEED_MODE"] = "users"
      load_seed

      user = User.find_by!(email: seed_email)

      expect(user.expense_entries).to be_empty
      expect(user.pay_schedules).to be_empty
      expect(user.subscriptions).to be_empty
      expect(user.monthly_bills).to be_empty
      expect(user.payment_plans).to be_empty
      expect(user.credit_cards).to be_empty
      expect(user.accounts).to be_empty
      expect(user.account_snapshots).to be_empty
    end
  end

  context "when only one admin seed variable is provided" do
    let(:seed_mode) { "users" }
    let(:seed_email) { "broken-admin-seed@example.com" }
    let(:admin_seed_email) { "admin@example.com" }

    it "raises an error" do
      expect { load_seed }.to raise_error(
        ArgumentError,
        "ADMIN_USER_EMAIL and ADMIN_USER_PASSWORD must both be provided to bootstrap an admin user"
      )
    end
  end
end
