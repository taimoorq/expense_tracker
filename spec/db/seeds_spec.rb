require "rails_helper"

RSpec.describe "db/seeds" do
  def load_seed
    Rails.application.load_seed
  end

  around do |example|
    original_mode = ENV["SEED_MODE"]
    original_email = ENV["SEED_USER_EMAIL"]
    original_password = ENV["SEED_USER_PASSWORD"]

    ENV["SEED_MODE"] = seed_mode
    ENV["SEED_USER_EMAIL"] = seed_email
    ENV["SEED_USER_PASSWORD"] = seed_password

    example.run
  ensure
    ENV["SEED_MODE"] = original_mode
    ENV["SEED_USER_EMAIL"] = original_email
    ENV["SEED_USER_PASSWORD"] = original_password
  end

  let(:seed_password) { "password123!" }

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
    end
  end
end
