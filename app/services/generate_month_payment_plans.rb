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
        account: plan.account_name,
        status: :planned,
        need_or_want: "Need",
        notes: "Remaining: #{plan.remaining_balance.to_f}",
        source_file: TemplateTypeRegistry.source_file_for(:payment_plan),
        source_template: plan
      )
      created += 1
    end

    created
  end

  private

  def exists?(plan, due_date)
    @budget_month.expense_entries.any? do |entry|
      plan.matches_entry?(entry, month_on: @budget_month.month_on) && entry.occurred_on == due_date
    end
  end
end
