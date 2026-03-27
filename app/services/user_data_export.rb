class UserDataExport
  SCOPES = %w[planning_templates budget_months accounts].freeze
  FORMAT_NAME = "expense_tracker_backup".freeze
  FORMAT_VERSION = 1

  attr_reader :scopes

  def initialize(user:, scopes:)
    @user = user
    @scopes = normalize_scopes(scopes)
  end

  def filename(password: nil)
    suffix = password.present? ? "-encrypted" : nil
    "expense-tracker-backup-#{Time.current.strftime('%Y%m%d-%H%M%S')}#{suffix}.json"
  end

  def as_json
    {
      format: FORMAT_NAME,
      version: FORMAT_VERSION,
      exported_at: Time.current.iso8601,
      scopes: scopes,
      data: export_data
    }
  end

  def to_json(*_args)
    JSON.pretty_generate(as_json)
  end

  def backup_json(password: nil)
    UserDataBackupCodec.encode(payload: as_json, password: password)
  end

  private

  attr_reader :user

  def normalize_scopes(requested_scopes)
    Array(requested_scopes).map(&:to_s) & SCOPES
  end

  def export_data
    {}.tap do |data|
      data[:planning_templates] = serialize_planning_templates if scopes.include?("planning_templates")
      data[:budget_months] = serialize_budget_months if scopes.include?("budget_months")
      data[:accounts] = serialize_accounts if scopes.include?("accounts")
    end
  end

  def serialize_planning_templates
    {
      pay_schedules: user.pay_schedules.order(:name).map do |record|
        {
          name: record.name,
          cadence: record.cadence,
          amount: decimal_string(record.amount),
          first_pay_on: record.first_pay_on&.to_s,
          day_of_month_one: record.day_of_month_one,
          day_of_month_two: record.day_of_month_two,
          weekend_adjustment: record.weekend_adjustment,
          account: PlanningTemplateAccountLinking.resolved_account_name(record),
          active: record.active
        }
      end,
      subscriptions: user.subscriptions.order(:due_day, :name).map do |record|
        {
          name: record.name,
          amount: decimal_string(record.amount),
          due_day: record.due_day,
          account: PlanningTemplateAccountLinking.resolved_account_name(record),
          notes: record.notes,
          active: record.active
        }
      end,
      monthly_bills: user.monthly_bills.order(:kind, :due_day, :name).map do |record|
        {
          name: record.name,
          kind: record.kind,
          default_amount: decimal_string(record.default_amount),
          due_day: record.due_day,
          billing_frequency: record.billing_frequency,
          billing_months: record.billing_months,
          account: PlanningTemplateAccountLinking.resolved_account_name(record),
          notes: record.notes,
          active: record.active
        }
      end,
      payment_plans: user.payment_plans.order(:due_day, :name).map do |record|
        {
          name: record.name,
          total_due: decimal_string(record.total_due),
          amount_paid: decimal_string(record.amount_paid),
          monthly_target: decimal_string(record.monthly_target),
          due_day: record.due_day,
          account: PlanningTemplateAccountLinking.resolved_account_name(record),
          notes: record.notes,
          active: record.active
        }
      end,
      credit_cards: user.credit_cards.order(:priority, :name).map do |record|
        {
          name: record.name,
          minimum_payment: decimal_string(record.minimum_payment),
          due_day: record.due_day,
          priority: record.priority,
          payment_account: record.payment_account&.name || record.account,
          linked_account: record.linked_account&.name,
          notes: record.notes,
          active: record.active
        }
      end
    }
  end

  def serialize_budget_months
    user.budget_months.includes(:expense_entries).order(:month_on).map do |month|
      {
        label: month.label,
        month_on: month.month_on&.to_s,
        leftover: decimal_string(month.leftover),
        notes: month.notes,
        expense_entries: month.expense_entries.chronological.map do |entry|
          {
            occurred_on: entry.occurred_on&.to_s,
            section: entry.section,
            category: entry.category,
            payee: entry.payee,
            planned_amount: decimal_string(entry.planned_amount),
            actual_amount: decimal_string(entry.actual_amount),
            account: entry.account,
            source_account: entry.source_account&.name,
            status: entry.status,
            need_or_want: entry.need_or_want,
            notes: entry.notes,
            source_file: entry.source_file,
            source_template_type: entry.source_template_type,
            source_template_name: entry.source_template&.name
          }
        end
      }
    end
  end

  def serialize_accounts
    user.accounts.includes(:account_snapshots).active_first.map do |account|
      {
        name: account.name,
        institution_name: account.institution_name,
        kind: account.kind,
        active: account.active,
        include_in_net_worth: account.include_in_net_worth,
        include_in_cash: account.include_in_cash,
        notes: account.notes,
        account_snapshots: account.account_snapshots.sort_by { |snapshot| [ snapshot.recorded_on, snapshot.created_at ] }.map do |snapshot|
          {
            recorded_on: snapshot.recorded_on&.to_s,
            balance: decimal_string(snapshot.balance),
            available_balance: decimal_string(snapshot.available_balance),
            notes: snapshot.notes
          }
        end
      }
    end
  end

  def decimal_string(value)
    return nil if value.nil?

    value.to_d.to_s("F")
  end
end
