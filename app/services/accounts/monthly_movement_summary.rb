module Accounts
  class MonthlyMovementSummary
    def initialize(budget_months:)
      @budget_months = Array(budget_months).sort_by(&:month_on)
      @entries_by_month_id = @budget_months.index_with { |month| month.expense_entries.to_a }
    end

    def payload
      {
        month_labels: month_labels,
        credit_card: {
          datasets: credit_card_datasets,
          added_total: total_for(card_added),
          paid_total: total_for(card_paid),
          planned_payment_total: total_for(card_planned_payments),
          account_count: credit_card_account_labels.count
        },
        bank_accounts: {
          datasets: bank_account_datasets,
          money_in_total: total_for(bank_money_in),
          paid_out_total: total_for(bank_paid_out),
          left_to_pay_total: total_for(bank_left_to_pay),
          account_count: bank_account_labels.count
        }
      }
    end

    private

    attr_reader :budget_months, :entries_by_month_id

    def month_labels
      @month_labels ||= budget_months.map { |month| month.month_on.strftime("%b %Y") }
    end

    def month_index_by_id
      @month_index_by_id ||= budget_months.each_with_index.to_h { |month, index| [ month.id, index ] }
    end

    def card_added
      @card_added ||= movement_bucket
    end

    def card_paid
      @card_paid ||= movement_bucket
    end

    def card_planned_payments
      @card_planned_payments ||= movement_bucket
    end

    def bank_money_in
      @bank_money_in ||= movement_bucket
    end

    def bank_paid_out
      @bank_paid_out ||= movement_bucket
    end

    def bank_left_to_pay
      @bank_left_to_pay ||= movement_bucket
    end

    def movement_bucket
      Hash.new { |hash, key| hash[key] = Array.new(budget_months.size, 0.to_d) }
    end

    def classify_entries
      return if defined?(@classified_entries)

      budget_months.each do |month|
        month_index = month_index_by_id.fetch(month.id)

        entries_by_month_id.fetch(month).each do |entry|
          amount = entry.effective_amount.to_d
          next if amount.zero? || entry.skipped?

          classify_credit_card_entry(entry, amount, month_index)
          classify_bank_entry(entry, amount, month_index)
        end
      end

      @classified_entries = true
    end

    def classify_credit_card_entry(entry, amount, month_index)
      if entry.paid? && entry.source_account&.credit_card? && !entry.income?
        card_added[entry.source_account.name][month_index] += amount
      end

      if entry.destination_account&.credit_card?
        bucket = entry.paid? ? card_paid : entry.planned? ? card_planned_payments : nil
        bucket[entry.destination_account.name][month_index] += amount if bucket
      end
    end

    def classify_bank_entry(entry, amount, month_index)
      return unless entry.source_account&.asset?

      if entry.paid? && entry.income?
        bank_money_in[entry.source_account.name][month_index] += amount
      elsif entry.paid?
        bank_paid_out[entry.source_account.name][month_index] += amount
      elsif entry.planned? && !entry.income?
        bank_left_to_pay[entry.source_account.name][month_index] += amount
      end
    end

    def credit_card_datasets
      classify_entries

      movement_datasets(
        labels: credit_card_account_labels,
        buckets: [
          [ "added", card_added, "rgba(244, 63, 94, 0.58)" ],
          [ "paid off", card_paid, "rgba(16, 185, 129, 0.58)" ],
          [ "planned payments", card_planned_payments, "rgba(14, 165, 233, 0.45)" ]
        ]
      )
    end

    def bank_account_datasets
      classify_entries

      movement_datasets(
        labels: bank_account_labels,
        buckets: [
          [ "money in", bank_money_in, "rgba(16, 185, 129, 0.58)" ],
          [ "paid out", bank_paid_out, "rgba(244, 63, 94, 0.58)" ],
          [ "left to pay", bank_left_to_pay, "rgba(245, 158, 11, 0.5)" ]
        ]
      )
    end

    def credit_card_account_labels
      classify_entries
      @credit_card_account_labels ||= (card_added.keys | card_paid.keys | card_planned_payments.keys).sort
    end

    def bank_account_labels
      classify_entries
      @bank_account_labels ||= (bank_money_in.keys | bank_paid_out.keys | bank_left_to_pay.keys).sort
    end

    def movement_datasets(labels:, buckets:)
      labels.flat_map do |account_label|
        buckets.filter_map do |movement_label, bucket, color|
          values = bucket[account_label].map { |value| value.round(2).to_f }
          next if values.all?(&:zero?)

          {
            label: "#{account_label} #{movement_label}",
            data: values,
            backgroundColor: color
          }
        end
      end
    end

    def total_for(bucket)
      classify_entries
      bucket.values.flatten.sum.round(2).to_f
    end
  end
end
