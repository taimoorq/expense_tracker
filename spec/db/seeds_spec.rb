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

    it "creates the user with reusable demo scaffolding but no month history" do
      expect { load_seed }.to change(User, :count).by(1)

      user = User.find_by!(email: seed_email)

      expect(user.valid_password?(seed_password)).to be(true)
      expect(user.budget_months).to be_empty
      expect(user.expense_entries).to be_empty
      expect(user.pay_schedules.count).to eq(2)
      expect(user.subscriptions.count).to eq(3)
      expect(user.monthly_bills.count).to eq(4)
      expect(user.payment_plans.count).to eq(2)
      expect(user.credit_cards.count).to eq(2)
      expect(user.accounts.count).to eq(9)
      expect(user.account_snapshots.count).to eq(27)
      expect(user.pay_schedules.find_by!(name: "Main Paycheck").linked_account&.name).to eq("Everyday Checking")
      expect(user.subscriptions.find_by!(name: "Streaming Service").linked_account&.name).to eq("Rewards Visa Balance")
      expect(user.payment_plans.find_by!(name: "Student Loan").linked_account&.name).to eq("Student Loan Balance")
      expect(user.credit_cards.find_by!(name: "Everyday Visa").payment_account&.name).to eq("Everyday Checking")
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
      expect(user.budget_months.count).to eq(6)
      expect(user.expense_entries).not_to be_empty
      expect(user.budget_months.order(:month_on).pluck(:month_on)).to eq((1..6).map { |offset| Date.current.beginning_of_month.prev_month(offset) }.sort)
      expect(user.pay_schedules.count).to eq(2)
      expect(user.subscriptions.count).to eq(3)
      expect(user.monthly_bills.count).to eq(4)
      expect(user.payment_plans.count).to eq(2)
      expect(user.credit_cards.count).to eq(2)
      expect(user.accounts.count).to eq(9)
      expect(user.account_snapshots.count).to eq(27)
      expect(user.accounts.find_by!(name: "Rewards Visa Balance").latest_balance.to_d).to eq((-412.38).to_d)
      expect(user.accounts.find_by!(name: "Emergency Savings").account_snapshots.count).to eq(3)
      expect(user.accounts.find_by!(name: "401(k) Portfolio").retirement?).to be(true)
      expect(user.credit_cards.find_by!(name: "Everyday Visa").linked_account&.name).to eq("Rewards Visa Balance")
      expect(user.credit_cards.find_by!(name: "Everyday Visa").payment_account&.name).to eq("Everyday Checking")
      expect(user.expense_entries.where(source_file: "seed:generated_history")).to exist
      expect(user.expense_entries.find_by(payee: "Performance Bonus")).to be_present
      expect(user.expense_entries.find_by(payee: "Emergency Plumber")).to be_present
    end

    it "can switch the same user back to users-only mode" do
      load_seed

      ENV["SEED_MODE"] = "users"
      load_seed

      user = User.find_by!(email: seed_email)

      expect(user.expense_entries).to be_empty
      expect(user.budget_months).to be_empty
      expect(user.pay_schedules.count).to eq(2)
      expect(user.subscriptions.count).to eq(3)
      expect(user.monthly_bills.count).to eq(4)
      expect(user.payment_plans.count).to eq(2)
      expect(user.credit_cards.count).to eq(2)
      expect(user.accounts.count).to eq(9)
      expect(user.account_snapshots.count).to eq(27)
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
