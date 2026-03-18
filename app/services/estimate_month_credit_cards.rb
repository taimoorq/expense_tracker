class EstimateMonthCreditCards
  def initialize(budget_month:, cards: budget_month.user.credit_cards.active_only)
    @budget_month = budget_month
    @cards = cards.to_a
  end

  def call
    return 0 if @cards.empty?

    remove_existing_estimates
    available = available_cash
    return 0 if available <= 0

    allocations = allocate(available)
    created = 0

    allocations.each do |card, amount|
      next if amount <= 0

      @budget_month.expense_entries.create!(
        occurred_on: estimated_due_date_for(card),
        section: :debt,
        category: "Credit Card",
        payee: card.name,
        planned_amount: amount.round(2),
        actual_amount: nil,
        account: card.account_name,
        status: :planned,
        need_or_want: "Need",
        notes: "Estimated from leftover cash",
        source_file: TemplateTypeRegistry.source_file_for(:credit_card),
        source_template: card
      )
      created += 1
    end

    created
  end

  private

  def available_cash
    non_card_outflow = @budget_month.expense_entries.reject do |entry|
      entry.section == "income" || entry.source_file == "credit_card_estimate"
    end.sum(&:effective_amount)

    [ @budget_month.income_total - non_card_outflow, 0 ].max
  end

  def allocate(available)
    allocations = Hash.new(0)
    remaining = available.to_d

    @cards.each do |card|
      min_pay = card.minimum_payment.to_d
      pay = [ min_pay, remaining ].min
      allocations[card] += pay
      remaining -= pay
      break if remaining <= 0
    end

    return allocations if remaining <= 0

    per_card_extra = remaining / @cards.count
    @cards.each { |card| allocations[card] += per_card_extra }
    allocations
  end

  def remove_existing_estimates
    @budget_month.expense_entries.where(source_file: TemplateTypeRegistry.source_file_for(:credit_card)).delete_all
  end

  def estimated_due_date_for(card)
    month_start = @budget_month.month_on.to_date.beginning_of_month
    month_start.change(day: [ card.due_day.to_i, month_start.end_of_month.day ].min)
  end
end
