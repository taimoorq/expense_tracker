class EstimateMonthCreditCards
  attr_reader :available_cash, :created_count, :skipped_count, :minimum_required

  def initialize(budget_month:, cards: budget_month.user.credit_cards.active_only)
    @budget_month = budget_month
    @cards = cards.to_a
    @available_cash = 0.to_d
    @created_count = 0
    @skipped_count = 0
    @minimum_required = 0.to_d
  end

  def call
    return 0 if @cards.empty?

    remove_existing_estimates
    @available_cash = calculated_available_cash
    allocations = allocate(@available_cash)
    @created_count = 0

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
      @created_count += 1
    end

    @skipped_count = @cards.count - @created_count
    @created_count
  end

  private

  def calculated_available_cash
    non_card_outflow = @budget_month.expense_entries.reject do |entry|
      entry.section == "income" || entry.source_file == "credit_card_estimate"
    end.sum(&:effective_amount)

    [ @budget_month.income_total - non_card_outflow, 0 ].max
  end

  def allocate(available)
    allocations = Hash.new(0)
    @minimum_required = @cards.sum { |card| card.minimum_payment.to_d }

    @cards.each do |card|
      allocations[card] += card.minimum_payment.to_d
    end

    remaining = available.to_d - @minimum_required
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
