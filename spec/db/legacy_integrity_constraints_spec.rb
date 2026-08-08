require "rails_helper"

RSpec.describe "legacy financial database integrity" do
  def foreign_key(table_name, name)
    ActiveRecord::Base.connection.foreign_keys(table_name).find { |key| key.name == name }
  end

  def check_constraint(table_name, name)
    ActiveRecord::Base.connection.check_constraints(table_name).find { |constraint| constraint.name == name }
  end

  it "validates same-owner foreign keys after the quality gate passes" do
    month_owner = foreign_key(:expense_entries, "fk_entries_month_owner")
    account_owner = foreign_key(:expense_entries, "fk_entries_source_account_owner")
    import_scope = foreign_key(:account_activities, "fk_activities_import_scope")

    expect(month_owner.column).to eq(%w[budget_month_id user_id])
    expect(month_owner.primary_key).to eq(%w[id user_id])
    expect(month_owner).to be_validated
    expect(account_owner.column).to eq(%w[source_account_id user_id])
    expect(account_owner).to be_validated
    expect(import_scope.column).to eq(%w[account_activity_import_id user_id account_id])
    expect(import_scope.primary_key).to eq(%w[id user_id account_id])
    expect(import_scope).to be_validated
  end

  it "rejects a new cross-owner month relationship below Active Record" do
    owner = create(:user)
    other_user = create(:user)
    month = create(:budget_month, user: owner)

    expect do
      ExpenseEntry.insert_all!(
        [
          {
            user_id: other_user.id,
            budget_month_id: month.id,
            section: ExpenseEntry.sections.fetch("fixed"),
            status: ExpenseEntry.statuses.fetch("planned"),
            source_file: "manual",
            created_at: Time.current,
            updated_at: Time.current
          }
        ]
      )
    end.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "rejects invalid financial values below Active Record" do
    user = create(:user)
    month = create(:budget_month, user: user)

    expect do
      ExpenseEntry.insert_all!(
        [
          {
            user_id: user.id,
            budget_month_id: month.id,
            planned_amount: -1,
            section: ExpenseEntry.sections.fetch("fixed"),
            status: ExpenseEntry.statuses.fetch("planned"),
            source_file: "manual",
            created_at: Time.current,
            updated_at: Time.current
          }
        ]
      )
    end.to raise_error(ActiveRecord::StatementInvalid, /expense_entries_planned_amount_nonnegative/)
  end

  it "validates financial checks after the legacy report is clean" do
    constraint = check_constraint(:budget_months, "budget_months_first_day")

    expect(constraint).not_to be_nil
    expect(constraint).to be_validated
  end

  it "uses optimistic locking for user-editable financial records" do
    account = create(:account)
    first_copy = Account.find(account.id)
    second_copy = Account.find(account.id)

    first_copy.update!(notes: "First change")

    expect { second_copy.update!(notes: "Conflicting change") }.to raise_error(ActiveRecord::StaleObjectError)
  end
end
