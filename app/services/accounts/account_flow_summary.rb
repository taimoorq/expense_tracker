module Accounts
  class AccountFlowSummary
    def initialize(expense_entries:)
      @entries = Array(expense_entries)
    end

    def payload
      {
        labels: account_rows.map { |row| row[:name] },
        charged_values: account_rows.map { |row| row[:charged_total] },
        paid_values: account_rows.map { |row| row[:paid_total] },
        charged_total: account_rows.sum { |row| row[:charged_total] }.round(2),
        paid_total: account_rows.sum { |row| row[:paid_total] }.round(2),
        account_count: account_rows.count,
        tracked_entries_count: tracked_entries_count,
        untracked_entries_count: untracked_entries_count,
        top_account: account_rows.first
      }
    end

    private

    attr_reader :entries

    def account_rows
      @account_rows ||= begin
        grouped_totals.map do |name, totals|
          charged_total = totals[:charged].round(2).to_f
          paid_total = totals[:paid].round(2).to_f

          {
            name: name,
            charged_total: charged_total,
            paid_total: paid_total,
            activity_total: (charged_total + paid_total).round(2)
          }
        end.sort_by { |row| [ -row[:activity_total], row[:name].downcase ] }
      end
    end

    def grouped_totals
      @grouped_totals ||= entries.each_with_object(Hash.new { |hash, key| hash[key] = { charged: 0.to_d, paid: 0.to_d } }) do |entry, totals|
        label, bucket = account_bucket_for(entry)
        next if label.blank? || bucket.blank?

        totals[label][bucket] += entry.effective_amount.to_d
      end
    end

    def tracked_entries_count
      @tracked_entries_count ||= entries.count do |entry|
        account_bucket_for(entry).first.present?
      end
    end

    def untracked_entries_count
      entries.size - tracked_entries_count
    end

    def account_bucket_for(entry)
      return [ payment_destination_label(entry), :paid ] if payment_to_account_entry?(entry)

      account_label = normalized_label(entry.account_name)
      return [ nil, nil ] if account_label.blank?
      return [ account_label, :paid ] if entry.income?

      [ account_label, :charged ]
    end

    def payment_to_account_entry?(entry)
      entry.source_template.is_a?(CreditCard) || entry.source_file == CreditCard.template_source_file
    end

    def payment_destination_label(entry)
      template = entry.source_template
      return normalized_label(template.linked_account&.name) if template.is_a?(CreditCard) && template.linked_account.present?
      return normalized_label(template.name) if template.is_a?(CreditCard)

      normalized_label(entry.payee)
    end

    def normalized_label(value)
      value.to_s.strip.presence
    end
  end
end
