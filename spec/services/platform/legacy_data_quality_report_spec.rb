require "rails_helper"

RSpec.describe Platform::LegacyDataQualityReport do
  def findings_by_key(report)
    report.findings.index_by(&:key)
  end

  it "reports a clean result for valid legacy records" do
    user = create(:user)
    account = create(:account, user: user)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1))
    create(:expense_entry, user: user, budget_month: month, source_account: account)

    report = described_class.call

    expect(report).to be_clean
    expect(report.violation_count).to eq(0)
    expect(report.as_json).to include(clean: true, violation_count: 0)
  end

  it "finds legacy calendar, provenance, and balance-evidence violations" do
    owner = create(:user)
    account = create(:account, user: owner)
    month = create(:budget_month, user: owner, month_on: Date.new(2026, 8, 1))
    entry = create(:expense_entry, user: owner, budget_month: month, source_account: account)
    monthly_bill = create(:monthly_bill, user: owner)
    generated_entry = create(
      :expense_entry,
      user: owner,
      budget_month: month,
      source_file: monthly_bill.template_source_file,
      source_template: monthly_bill,
      generated_entry_key: nil
    )
    activity_import = create(:account_activity_import, user: owner, account: account)

    entry.update_column(:occurred_on, Date.new(2026, 9, 1))
    activity_import.update_column(:metadata, { "institution_balance" => "250.00" })

    findings = findings_by_key(described_class.call)

    expect(findings.fetch(:expense_entry_outside_month).sample_identifiers).to include(entry.id)
    expect(findings.fetch(:generated_entry_missing_durable_key).sample_identifiers).to include(generated_entry.id)
    expect(findings.fetch(:institution_balance_missing_as_of).sample_identifiers).to include(activity_import.id)
  end

  it "does not report a legitimate pay-schedule weekend adjustment across a month boundary" do
    user = create(:user)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 2, 1))
    schedule = create(
      :pay_schedule,
      user: user,
      cadence: :monthly,
      first_pay_on: Date.new(2026, 2, 1),
      day_of_month_one: 28,
      weekend_adjustment: :next_monday
    )
    create(
      :expense_entry,
      user: user,
      budget_month: month,
      occurred_on: Date.new(2026, 3, 2),
      source_file: schedule.template_source_file,
      source_template: schedule,
      generated_entry_key: schedule.generated_entry_key(month_on: month.month_on, occurred_on: Date.new(2026, 3, 2))
    )

    finding = findings_by_key(described_class.call).fetch(:expense_entry_outside_month)

    expect(finding).to be_clean
  end

  it "rejects a non-positive sample limit" do
    expect { described_class.call(sample_limit: 0) }.to raise_error(ArgumentError, "sample_limit must be positive")
  end
end
