class GenerateMonthPaymentPlans
  def initialize(budget_month:, plans: budget_month.user.payment_plans.active_only)
    @budget_month = budget_month
    @plans = plans
  end

  def call
    created = 0

    @plans.find_each do |plan|
      payment_amount = plan.monthly_amount
      next if payment_amount.to_d <= 0

      due_date = plan.due_date_for_month(@budget_month.month_on)
      next if exists?(plan, due_date)

      @budget_month.expense_entries.create!(
        occurred_on: due_date,
        section: :debt,
        category: "Payment Plan",
        payee: plan.name,
        planned_amount: payment_amount,
        actual_amount: nil,
        account: plan.account,
        status: :planned,
        need_or_want: "Need",
        notes: "Remaining: #{plan.remaining_balance.to_f}",
        source_file: "payment_plan"
      )
      created += 1
    end

    created
  end

  private

  def exists?(plan, due_date)
    @budget_month.expense_entries.exists?(
      section: ExpenseEntry.sections[:debt],
      payee: plan.name,
      occurred_on: due_date,
      source_file: "payment_plan"
    )
  end
end
