class GenerateMonthSubscriptions
  def initialize(budget_month:, subscriptions: budget_month.user.subscriptions.active_only)
    @budget_month = budget_month
    @subscriptions = subscriptions
  end

  def call
    created = 0

    @subscriptions.find_each do |subscription|
      due_date = subscription.due_date_for_month(@budget_month.month_on)
      next if exists?(subscription, due_date)

      @budget_month.expense_entries.create!(
        occurred_on: due_date,
        section: :fixed,
        category: "Subscription",
        payee: subscription.name,
        planned_amount: subscription.amount,
        actual_amount: nil,
        account: subscription.account_name,
        status: :planned,
        need_or_want: "Need",
        notes: subscription.notes,
        source_file: TemplateTypeRegistry.source_file_for(:subscription),
        source_template: subscription
      )
      created += 1
    end

    created
  end

  private

  def exists?(subscription, due_date)
    @budget_month.expense_entries.any? do |entry|
      subscription.matches_entry?(entry, month_on: @budget_month.month_on) && entry.occurred_on == due_date
    end
  end
end
