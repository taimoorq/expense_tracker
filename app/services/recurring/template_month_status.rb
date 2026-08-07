module Recurring
  class TemplateMonthStatus
    Result = Data.define(:status, :label, :prefill, :extra_occurrence_required?)

    def self.call(template:, budget_month:, entries: budget_month.expense_entries.to_a)
      new(template: template, budget_month: budget_month, entries: entries).call
    end

    def initialize(template:, budget_month:, entries:)
      @template = template
      @budget_month = budget_month
      @entries = Array(entries).select(&:persisted?)
    end

    def call
      return credit_card_result if template.is_a?(CreditCard)

      recurring_result
    end

    private

    attr_reader :template, :budget_month, :entries

    def recurring_result
      coverage = MonthTemplateCoverage.new(template: template, budget_month: budget_month, entries: entries)
      row = coverage.missing_rows.first || coverage.rows.first

      if row.blank?
        occurred_on = fallback_occurrence
        return Result.new(
          status: :not_scheduled,
          label: "Not scheduled for #{budget_month.label}",
          prefill: scalar_prefill(generated_attributes_for(occurred_on)),
          extra_occurrence_required?: true
        )
      end

      if coverage.remaining.positive?
        label = if coverage.matched.positive?
          "#{coverage.matched} of #{coverage.total} already added · next #{short_date(row.occurred_on)}"
        else
          "Ready to add · #{short_date(row.occurred_on)}"
        end

        return Result.new(
          status: :missing,
          label: label,
          prefill: scalar_prefill(row.attributes),
          extra_occurrence_required?: false
        )
      end

      alternate_row = coverage.alternate_rows.first
      status = alternate_row.present? ? :found_another_date : :already_added
      label = if alternate_row.present?
        "Found on #{short_date(alternate_row.entry.occurred_on)} instead of #{short_date(alternate_row.occurred_on)}"
      else
        "Already added for #{budget_month.label}"
      end

      Result.new(
        status: status,
        label: label,
        prefill: scalar_prefill(row.attributes),
        extra_occurrence_required?: true
      )
    end

    def credit_card_result
      attributes = template.build_estimated_entry_attributes(month_on: budget_month.month_on, amount: template.minimum_payment)
      matching_entry = entries.find { |entry| template.matches_entry_for_month?(entry, month_on: budget_month.month_on) }

      if matching_entry.blank?
        return Result.new(
          status: :missing,
          label: "Ready to add · #{short_date(attributes[:occurred_on])}",
          prefill: scalar_prefill(attributes),
          extra_occurrence_required?: false
        )
      end

      expected_on = attributes[:occurred_on]
      found_elsewhere = matching_entry.occurred_on != expected_on

      Result.new(
        status: found_elsewhere ? :found_another_date : :already_added,
        label: found_elsewhere ? "Found on #{short_date(matching_entry.occurred_on)} instead of #{short_date(expected_on)}" : "Already added for #{budget_month.label}",
        prefill: scalar_prefill(attributes),
        extra_occurrence_required?: true
      )
    end

    def scalar_prefill(attributes)
      attributes = attributes.to_h.with_indifferent_access
      source_account = template.respond_to?(:entry_account_record) ? template.entry_account_record : nil
      destination_account = template.is_a?(CreditCard) ? template.linked_account : nil

      {
        occurred_on: attributes[:occurred_on]&.to_date&.iso8601,
        section: attributes[:section]&.to_s,
        category: attributes[:category].to_s,
        payee: attributes[:payee].to_s,
        planned_amount: attributes[:planned_amount]&.to_s,
        actual_amount: attributes[:actual_amount]&.to_s,
        status: attributes[:status]&.to_s.presence || "planned",
        need_or_want: attributes[:need_or_want].to_s,
        notes: attributes[:notes].to_s,
        account: source_account&.name.presence || attributes[:account].to_s,
        source_account_id: source_account&.id,
        destination_account_id: destination_account&.id
      }
    end

    def generated_attributes_for(occurred_on)
      return {} if occurred_on.blank?

      template.build_generated_entry_attributes(month_on: budget_month.month_on, occurred_on: occurred_on)
    end

    def fallback_occurrence
      return template.due_date_for_month(budget_month.month_on) if template.respond_to?(:due_date_for_month)

      budget_month.month_on.to_date
    end

    def short_date(date)
      date&.strftime("%b %-d") || budget_month.label
    end
  end
end
