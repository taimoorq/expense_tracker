module Accounts
  class MonthlyMovementSummary
    def initialize(budget_months:, expense_entries: nil)
      @budget_months = Array(budget_months).sort_by(&:month_on)
      @entries_by_month_id = entries_by_month(expense_entries)
    end

    def payload
      {
        month_labels: month_labels,
        credit_card: {
          datasets: credit_card_datasets,
          added_total: total_for(card_added),
          paid_total: total_for(card_paid),
          planned_payment_total: total_for(card_planned_payments),
          account_count: credit_card_account_labels.count,
          drilldowns: drilldowns_for(%w[credit_card_added credit_card_paid credit_card_planned])
        },
        bank_accounts: {
          datasets: bank_account_datasets,
          money_in_total: total_for(bank_money_in),
          paid_out_total: total_for(bank_paid_out),
          left_to_pay_total: total_for(bank_left_to_pay),
          account_count: bank_account_labels.count,
          drilldowns: drilldowns_for(%w[bank_money_in bank_paid_out bank_left_to_pay])
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

        entries_by_month_id.fetch(month.id).each do |entry|
          movement_accounts_for(entry).each do |account|
            impact = Accounts::EntryImpact.new(account: account, entry: entry)
            movement_type = impact.movement_type
            next if movement_type.blank?

            bucket_for(movement_type)[account.name][month_index] += impact.amount
            add_drilldown(movement_type, account, month_index, impact.amount)
          end
        end
      end

      @classified_entries = true
    end

    def movement_accounts_for(entry)
      [ entry.source_account, entry.destination_account ].compact.uniq
    end

    def entries_by_month(expense_entries)
      return budget_months.index_with { |month| month.expense_entries.to_a }.transform_keys(&:id) if expense_entries.nil?

      grouped_entries = Array(expense_entries).group_by(&:budget_month_id)
      budget_months.to_h { |month| [ month.id, grouped_entries.fetch(month.id, []) ] }
    end

    def bucket_for(movement_type)
      {
        "credit_card_added" => card_added,
        "credit_card_paid" => card_paid,
        "credit_card_planned" => card_planned_payments,
        "bank_money_in" => bank_money_in,
        "bank_paid_out" => bank_paid_out,
        "bank_left_to_pay" => bank_left_to_pay
      }.fetch(movement_type)
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

    def drilldown_bucket
      @drilldown_bucket ||= Hash.new { |hash, key| hash[key] = { amount: 0.to_d, entry_count: 0 } }
    end

    def add_drilldown(movement_type, account, month_index, amount)
      month = budget_months.fetch(month_index)
      key = [ movement_type, account.id, month.id ]
      drilldown_bucket[key][:movement_type] = movement_type
      drilldown_bucket[key][:account_id] = account.id
      drilldown_bucket[key][:account_name] = account.name
      drilldown_bucket[key][:budget_month_id] = month.id
      drilldown_bucket[key][:month_label] = month.label
      drilldown_bucket[key][:month_on] = month.month_on
      drilldown_bucket[key][:amount] += amount
      drilldown_bucket[key][:entry_count] += 1
    end

    def drilldowns_for(movement_types)
      classify_entries

      drilldown_bucket.values
                      .select { |item| movement_types.include?(item.fetch(:movement_type)) }
                      .sort_by { |item| [ item.fetch(:month_on), item.fetch(:account_name), item.fetch(:movement_type) ] }
                      .reverse
                      .map do |item|
        item.merge(
          movement_label: movement_label(item.fetch(:movement_type)),
          amount: item.fetch(:amount).round(2).to_f
        )
      end
    end

    def movement_label(movement_type)
      Accounts::EntryImpact::MOVEMENT_LABELS.fetch(movement_type)
    end
  end
end
