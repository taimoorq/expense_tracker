class AutoCompleteRecurringEntries
  def initialize(entries: ExpenseEntry.all, as_of: Date.current)
    @entries = entries
    @as_of = as_of
  end

  def call
    completed = 0

    scope.find_each do |entry|
      entry.update!(
        status: :paid,
        actual_amount: entry.actual_amount.presence || entry.planned_amount
      )
      completed += 1
    end

    completed
  end

  private

  def scope
    @entries
      .recurring_templates
      .where(status: :planned)
      .where.not(occurred_on: nil)
      .due_on_or_before(@as_of)
  end
end
