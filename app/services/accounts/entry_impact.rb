module Accounts
  class EntryImpact
    MOVEMENT_LABELS = {
      "credit_card_added" => "Added",
      "credit_card_paid" => "Paid off",
      "credit_card_planned" => "Planned payment",
      "bank_money_in" => "Money in",
      "bank_paid_out" => "Paid out",
      "bank_left_to_pay" => "Left to pay"
    }.freeze

    MOVEMENT_TITLES = {
      "credit_card_added" => "Credit card charges added",
      "credit_card_paid" => "Credit card payments made",
      "credit_card_planned" => "Planned credit card payments",
      "bank_money_in" => "Bank money in",
      "bank_paid_out" => "Bank paid out",
      "bank_left_to_pay" => "Bank left to pay"
    }.freeze

    attr_reader :account, :entry

    def initialize(account:, entry:)
      @account = account
      @entry = entry
    end

    def affects_account?
      source_entry? || destination_entry?
    end

    def amount
      entry.effective_amount.to_d
    end

    def delta
      return 0.to_d if entry.skipped?
      return 0.to_d unless affects_account?

      signed_delta = 0.to_d
      signed_delta += entry.income? ? amount : -amount if source_entry?
      signed_delta += amount if destination_entry?
      signed_delta
    end

    def movement_type
      return nil if entry.skipped? || amount.zero?

      credit_card_movement_type || bank_movement_type
    end

    private

    def source_entry?
      entry.source_account_id == account.id
    end

    def destination_entry?
      entry.destination_account_id == account.id
    end

    def credit_card_movement_type
      return nil unless account.credit_card?

      return "credit_card_added" if entry.paid? && source_entry? && !entry.income?
      return "credit_card_paid" if entry.paid? && destination_entry?
      return "credit_card_planned" if entry.planned? && destination_entry?

      nil
    end

    def bank_movement_type
      return nil unless account.asset? && source_entry?

      return "bank_money_in" if entry.paid? && entry.income?
      return "bank_paid_out" if entry.paid? && !entry.income?
      return "bank_left_to_pay" if entry.planned? && !entry.income?

      nil
    end
  end
end
