class GenerateMonthMonthlyBills
  def initialize(budget_month:, bills: MonthlyBill.active_only)
    @budget_month = budget_month
    @bills = bills
  end

  def call
    created = 0

    @bills.find_each do |bill|
      due_date = bill.due_date_for_month(@budget_month.month_on)
      next if exists?(bill, due_date)

      @budget_month.expense_entries.create!(
        occurred_on: due_date,
        section: section_for(bill),
        category: category_for(bill),
        payee: bill.name,
        planned_amount: bill.default_amount,
        actual_amount: nil,
        account: bill.account,
        status: :planned,
        need_or_want: "Need",
        notes: bill.notes,
        source_file: "monthly_bill"
      )
      created += 1
    end

    created
  end

  private

  def section_for(bill)
    bill.fixed_payment? ? :fixed : :manual
  end

  def category_for(bill)
    bill.fixed_payment? ? "Monthly Payment" : "Variable Bill"
  end

  def exists?(bill, due_date)
    @budget_month.expense_entries.exists?(
      payee: bill.name,
      occurred_on: due_date,
      source_file: "monthly_bill"
    )
  end
end
