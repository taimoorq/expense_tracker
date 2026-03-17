class UserDataImport
  SCOPES = UserDataExport::SCOPES

  def initialize(user:, payload:, scopes:)
    @user = user
    @payload = payload.deep_symbolize_keys
    @scopes = normalize_scopes(scopes)
  end

  def call
    return failure("Choose at least one section to import.") if scopes.empty?

    data = payload.fetch(:data, {})
    missing_scope = scopes.find { |scope| !data.key?(scope.to_sym) }
    return failure("The backup file does not include #{missing_scope.humanize.downcase}.") if missing_scope

    counts = {}

    ApplicationRecord.transaction do
      counts[:planning_templates] = import_planning_templates(data[:planning_templates]) if scopes.include?("planning_templates")
      counts[:budget_months] = import_budget_months(data[:budget_months]) if scopes.include?("budget_months")
      counts[:accounts] = import_accounts(data[:accounts]) if scopes.include?("accounts")
    end

    { success: true, counts: counts }
  rescue ActiveRecord::RecordInvalid => error
    failure(error.record.errors.full_messages.to_sentence.presence || error.message)
  end

  private

  attr_reader :payload, :scopes, :user

  def normalize_scopes(requested_scopes)
    Array(requested_scopes).map(&:to_s) & SCOPES
  end

  def import_planning_templates(data)
    user.pay_schedules.destroy_all
    user.subscriptions.destroy_all
    user.monthly_bills.destroy_all
    user.payment_plans.destroy_all
    user.credit_cards.destroy_all

    {
      pay_schedules: Array(data[:pay_schedules]).count do |attributes|
        user.pay_schedules.create!(attributes.slice(:name, :cadence, :amount, :first_pay_on, :day_of_month_one, :day_of_month_two, :weekend_adjustment, :account, :active))
      end,
      subscriptions: Array(data[:subscriptions]).count do |attributes|
        user.subscriptions.create!(attributes.slice(:name, :amount, :due_day, :account, :notes, :active))
      end,
      monthly_bills: Array(data[:monthly_bills]).count do |attributes|
        user.monthly_bills.create!(attributes.slice(:name, :kind, :default_amount, :due_day, :account, :active))
      end,
      payment_plans: Array(data[:payment_plans]).count do |attributes|
        user.payment_plans.create!(attributes.slice(:name, :total_due, :amount_paid, :monthly_target, :due_day, :account, :active))
      end,
      credit_cards: Array(data[:credit_cards]).count do |attributes|
        user.credit_cards.create!(attributes.slice(:name, :minimum_payment, :due_day, :priority, :account, :active))
      end
    }
  end

  def import_budget_months(data)
    user.budget_months.destroy_all

    month_count = 0
    entry_count = 0

    Array(data).each do |attributes|
      month = user.budget_months.create!(attributes.slice(:label, :month_on, :leftover, :notes))
      month_count += 1

      Array(attributes[:expense_entries]).each do |entry_attributes|
        month.expense_entries.create!(entry_attributes.slice(:occurred_on, :section, :category, :payee, :planned_amount, :actual_amount, :account, :status, :need_or_want, :notes, :source_file))
        entry_count += 1
      end
    end

    { months: month_count, entries: entry_count }
  end

  def import_accounts(data)
    user.accounts.destroy_all

    account_count = 0
    snapshot_count = 0

    Array(data).each do |attributes|
      account = user.accounts.create!(attributes.slice(:name, :institution_name, :kind, :active, :include_in_net_worth, :include_in_cash, :notes))
      account_count += 1

      Array(attributes[:account_snapshots]).each do |snapshot_attributes|
        account.account_snapshots.create!(snapshot_attributes.slice(:recorded_on, :balance, :available_balance, :notes))
        snapshot_count += 1
      end
    end

    { accounts: account_count, snapshots: snapshot_count }
  end

  def failure(message)
    { success: false, error: message }
  end
end
