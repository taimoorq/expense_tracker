class GenerateMonthPaychecks
  def initialize(budget_month:, schedules: budget_month.user.pay_schedules.active_only)
    @budget_month = budget_month
    @schedules = schedules
  end

  def call
    created = 0

    @schedules.find_each do |schedule|
      schedule.pay_dates_for_month(@budget_month.month_on).each do |pay_date|
        next if already_exists?(schedule, pay_date)

        @budget_month.expense_entries.create!(
          occurred_on: pay_date,
          section: :income,
          category: "Paycheck",
          payee: schedule.name,
          planned_amount: schedule.amount,
          actual_amount: nil,
          account: schedule.account_name,
          status: :planned,
          need_or_want: "Need",
          notes: "Generated from pay schedule",
          source_file: TemplateTypeRegistry.source_file_for(:pay_schedule),
          source_template: schedule
        )
        created += 1
      end
    end

    created
  end

  private

  def already_exists?(schedule, pay_date)
    @budget_month.expense_entries.any? do |entry|
      schedule.matches_entry?(entry, month_on: @budget_month.month_on) && entry.occurred_on == pay_date
    end
  end
end
