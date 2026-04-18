require "test_helper"

class BudgetMonthTest < ActiveSupport::TestCase
  test "totals reuse loaded expense_entries without extra queries" do
    user = User.create!(email: "budget-month-test@example.com", password: "password123", password_confirmation: "password123")
    month = user.budget_months.create!(label: "April 2026", month_on: Date.new(2026, 4, 1))
    month.expense_entries.create!(user: user, section: :income, status: :paid, payee: "Payroll", actual_amount: 3000)
    month.expense_entries.create!(user: user, section: :fixed, status: :planned, payee: "Rent", planned_amount: 1200)
    month.expense_entries.create!(user: user, section: :variable, status: :paid, payee: "Groceries", actual_amount: 250)

    loaded_month = BudgetMonth.includes(:expense_entries).find(month.id)
    loaded_month.expense_entries.load

    queries = capture_sql_queries do
      assert_equal BigDecimal("3000"), loaded_month.income_total
      assert_equal BigDecimal("1450"), loaded_month.outflow_total
      assert_equal BigDecimal("1550"), loaded_month.calculated_leftover
      assert_equal BigDecimal("250"), loaded_month.section_total(:variable)
    end

    assert_empty queries
  end

  private

  def capture_sql_queries
    queries = []
    callback = lambda do |_name, _started, _finished, _unique_id, payload|
      sql = payload[:sql].to_s
      next if payload[:cached]
      next if sql.match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT)/)
      next if payload[:name].to_s.include?("SCHEMA")

      queries << sql
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries
  end
end
