require "rails_helper"

RSpec.describe "Concurrent recurring review", type: :model do
  self.use_transactional_tests = false
  include RecurringCandidateHelpers

  before { @user = create(:user) }
  after do
    @user.recurring_candidate_decisions.destroy_all
    @user.budget_months.destroy_all
    @user.subscriptions.destroy_all
    @user.account_activity_imports.destroy_all
    @user.reload.destroy!
  end

  def race(*operations)
    ready = Queue.new
    start = Queue.new
    threads = operations.map do |operation|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          operation.call
        end
      end
    end
    operations.size.times { ready.pop }
    operations.size.times { start << true }
    threads.map(&:value)
  end

  it "serializes two initial submissions into one template and one decision" do
    account, candidate = recurring_candidate(user: @user)
    args = candidate_arguments(user: @user, account: account, candidate: candidate)
    save = -> { Accounts::RecurringCandidates::Resolve.call(**args.merge(user: User.find(@user.id), account: Account.find(account.id))).id }
    results = race(save, save)
    expect(results.uniq.size).to eq(1)
    expect(@user.subscriptions.count).to eq(1)
    expect(account.recurring_candidate_decisions.count).to eq(1)
  end

  it "serializes optional month insertion against normal recurring generation" do
    account = create(:account, user: @user)
    template = create(:subscription, user: @user, linked_account: account, name: "Cloud", amount: 12, due_day: 8)
    month = create(:budget_month, user: @user, month_on: Date.new(2026, 9, 1))
    digest = Recurring::AddTemplateToMonth.new(user: @user, template: template, budget_month: month).preview.digest
    race(
      -> { Recurring::AddTemplateToMonth.new(user: User.find(@user.id), template: Subscription.find(template.id), budget_month: BudgetMonth.find(month.id)).call(expected_digest: digest) },
      -> { Recurring::GenerateMonthRecurringEntries.new(budget_month: BudgetMonth.find(month.id), templates: [ Subscription.find(template.id) ]).call }
    )
    expect(month.expense_entries.count).to eq(1)
    expect(month.expense_entries.reload.sole.status).to eq("planned")
  end
end
