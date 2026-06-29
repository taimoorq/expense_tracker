module Recurring
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

      @budget_month.with_lock do
        @available_cash = calculated_available_cash
        allocations = allocate(@available_cash)
        @created_count = 0
        allocation_keys = allocations.keys.map { |card| card.estimated_entry_key(month_on: @budget_month.month_on) }.compact

        remove_stale_untouched_estimates(allocation_keys)

        allocations.each do |card, amount|
          next if amount <= 0

          @created_count += 1 if create_or_update_estimate(card, amount)
        end

        @skipped_count = @cards.count - @created_count
        @created_count
      end
    end

    private

    def calculated_available_cash
      non_card_outflow = @budget_month.expense_entries.reject do |entry|
        entry.section == "income" || replaceable_estimate?(entry)
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

    def create_or_update_estimate(card, amount)
      attributes = card.build_estimated_entry_attributes(month_on: @budget_month.month_on, amount: amount)
      existing_entry = existing_estimate_for(card, attributes[:generated_entry_key])

      if existing_entry.present?
        return false unless replaceable_estimate?(existing_entry, card: card)

        existing_entry.assign_attributes(attributes)
        existing_entry.save!(touch: false)
        return true
      end

      @budget_month.expense_entries.create!(attributes)
      true
    end

    def remove_stale_untouched_estimates(active_generated_keys)
      planned_estimates.find_each do |entry|
        next if active_generated_keys.include?(entry.generated_entry_key)
        next unless replaceable_estimate?(entry)

        entry.destroy!
      end
    end

    def existing_estimate_for(card, generated_key)
      keyed_entry = planned_estimates.find_by(generated_entry_key: generated_key) if generated_key.present?
      return keyed_entry if keyed_entry.present?

      planned_estimates.to_a.find do |entry|
        entry.generated_entry_key.blank? && card.matches_entry_for_month?(entry, month_on: @budget_month.month_on)
      end
    end

    def planned_estimates
      @budget_month.expense_entries.where(
        source_file: CreditCard.template_source_file,
        status: ExpenseEntry.statuses[:planned]
      )
    end

    def replaceable_estimate?(entry, card: nil)
      return false unless entry.source_file == CreditCard.template_source_file && entry.planned?
      return false if entry.actual_amount.present?
      return false if card.present? && !card.matches_entry_for_month?(entry, month_on: @budget_month.month_on)

      untouched_generated_estimate?(entry)
    end

    def untouched_generated_estimate?(entry)
      return false if entry.updated_at.blank? || entry.created_at.blank?

      entry.updated_at <= entry.created_at + 1.second
    end
  end
end
