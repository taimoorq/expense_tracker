class UserDataImportPreview
  SCOPES = UserDataExport::SCOPES

  def initialize(payload:, scopes:)
    @payload = payload.deep_symbolize_keys
    @scopes = Array(scopes).map(&:to_s) & SCOPES
  end

  def call
    return failure("Choose at least one section to import.") if scopes.empty?

    data = payload.fetch(:data, {})
    missing_scope = scopes.find { |scope| !data.key?(scope.to_sym) }
    return failure("The backup file does not include #{missing_scope.humanize.downcase}.") if missing_scope

    {
      success: true,
      summary: {
        sample_backup: payload[:sample_backup] == true,
        sample_notice: payload[:sample_notice],
        exported_at: payload[:exported_at],
        file_scopes: Array(payload[:scopes]),
        selected_scopes: scopes,
        planning_templates: planning_template_summary(data[:planning_templates]),
        budget_months: budget_month_summary(data[:budget_months]),
        accounts: account_summary(data[:accounts])
      }
    }
  end

  private

  attr_reader :payload, :scopes

  def planning_template_summary(data)
    return nil unless scopes.include?("planning_templates")

    template_counts = {
      pay_schedules: Array(data[:pay_schedules]).size,
      subscriptions: Array(data[:subscriptions]).size,
      monthly_bills: Array(data[:monthly_bills]).size,
      payment_plans: Array(data[:payment_plans]).size,
      credit_cards: Array(data[:credit_cards]).size
    }

    {
      total: template_counts.values.sum,
      counts: template_counts
    }
  end

  def budget_month_summary(data)
    return nil unless scopes.include?("budget_months")

    months = Array(data)
    {
      months: months.size,
      entries: months.sum { |month| Array(month[:expense_entries]).size }
    }
  end

  def account_summary(data)
    return nil unless scopes.include?("accounts")

    accounts = Array(data)
    {
      accounts: accounts.size,
      snapshots: accounts.sum { |account| Array(account[:account_snapshots]).size }
    }
  end

  def failure(message)
    { success: false, error: message }
  end
end
