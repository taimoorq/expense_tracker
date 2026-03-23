class GenerateMonthMonthlyBills
  def initialize(budget_month:, bills: budget_month.user.monthly_bills.active_only)
    @budget_month = budget_month
    @bills = bills
  end

  def call
    created = 0

    @bills.find_each do |bill|
      next unless bill.scheduled_for_month?(@budget_month.month_on)

      due_date = bill.due_date_for_month(@budget_month.month_on)
      next if exists?(bill, due_date)

      @budget_month.expense_entries.create!(
        occurred_on: due_date,
        section: section_for(bill),
        category: category_for(bill),
        payee: bill.name,
        planned_amount: bill.default_amount,
        actual_amount: nil,
        account: bill.account_name,
        status: :planned,
        need_or_want: "Need",
        notes: bill.notes,
        source_file: TemplateTypeRegistry.source_file_for(:monthly_bill),
        source_template: bill
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
    @budget_month.expense_entries.any? do |entry|
      bill.matches_entry?(entry, month_on: @budget_month.month_on) && entry.occurred_on == due_date
    end
  end
end
