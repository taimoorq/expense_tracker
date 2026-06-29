require "set"

module Recurring
  class MonthTemplateCoverage
    Match = Struct.new(:occurred_on, :status, :entry, :attributes, keyword_init: true) do
      def missing?
        status == :missing
      end

      def matched?
        !missing?
      end

      def alternate_date?
        status == :alternate_date
      end

      def preview
        return generated_preview if missing?

        {
          payee: entry.payee.presence || attributes[:payee],
          occurred_on: occurred_on,
          matched_on: entry.occurred_on,
          planned_amount: matched_amount,
          account: entry.account_name.presence || attributes[:account],
          category: entry.category.presence || attributes[:category]
        }
      end

      private

      def generated_preview
        {
          payee: attributes[:payee],
          occurred_on: occurred_on,
          planned_amount: attributes[:planned_amount],
          account: attributes[:account],
          category: attributes[:category]
        }
      end

      def matched_amount
        return entry.effective_amount if entry.respond_to?(:effective_amount)

        entry.actual_amount.presence || entry.planned_amount
      end
    end

    def initialize(template:, budget_month:, entries:)
      @template = template
      @budget_month = budget_month
      @entries = Array(entries)
    end

    attr_reader :template, :budget_month, :entries

    def rows
      @rows ||= build_rows
    end

    def matched_occurrence?(occurred_on)
      rows.any? { |row| row.occurred_on == occurred_on.to_date && row.matched? }
    end

    def total
      rows.size
    end

    def matched
      matched_rows.size
    end

    def remaining
      missing_rows.size
    end

    def complete?
      total.positive? && remaining.zero?
    end

    def matched_rows
      rows.reject(&:missing?)
    end

    def missing_rows
      rows.select(&:missing?)
    end

    def alternate_rows
      rows.select(&:alternate_date?)
    end

    def summary
      {
        total: total,
        matched: matched,
        remaining: remaining,
        complete: complete?,
        previews: sort_previews(missing_rows.map(&:preview)),
        alternate_count: alternate_rows.size,
        alternate_previews: sort_previews(alternate_rows.map(&:preview))
      }
    end

    private

    def build_rows
      used_entry_keys = Set.new
      exact_rows = occurrences.map do |occurred_on|
        attributes = template.build_generated_entry_attributes(month_on: budget_month.month_on, occurred_on: occurred_on)
        entry = exact_entry_for(occurred_on, used_entry_keys)

        if entry.present?
          used_entry_keys.add(entry_key(entry))
          Match.new(
            occurred_on: occurred_on,
            status: entry.occurred_on == occurred_on ? :exact : :alternate_date,
            entry: entry,
            attributes: attributes
          )
        else
          Match.new(occurred_on: occurred_on, status: :missing, attributes: attributes)
        end
      end

      exact_rows.map do |row|
        next row unless row.missing?

        entry = alternate_entry_for(row.occurred_on, used_entry_keys)
        next row if entry.blank?

        used_entry_keys.add(entry_key(entry))
        Match.new(occurred_on: row.occurred_on, status: :alternate_date, entry: entry, attributes: row.attributes)
      end
    end

    def exact_entry_for(occurred_on, used_entry_keys)
      generated_key = template.generated_entry_key(month_on: budget_month.month_on, occurred_on: occurred_on)

      keyed_entry = ordered_entries.find do |entry|
        unused_entry?(entry, used_entry_keys) &&
          generated_key.present? &&
          entry.generated_entry_key == generated_key
      end
      return keyed_entry if keyed_entry.present?

      ordered_entries.find do |entry|
        unused_entry?(entry, used_entry_keys) &&
          entry.occurred_on == occurred_on &&
          template.matches_entry_for_month?(entry, month_on: budget_month.month_on)
      end
    end

    def alternate_entry_for(occurred_on, used_entry_keys)
      ordered_entries
        .select { |entry| unused_entry?(entry, used_entry_keys) && template.represents_entry_for_month?(entry, month_on: budget_month.month_on) }
        .min_by { |entry| [ date_distance(entry.occurred_on, occurred_on), entry.occurred_on || Date.new(9999, 12, 31), entry.payee.to_s.downcase ] }
    end

    def ordered_entries
      @ordered_entries ||= entries.sort_by do |entry|
        [ entry.occurred_on || Date.new(9999, 12, 31), entry.payee.to_s.downcase, entry_key(entry).to_s ]
      end
    end

    def occurrences
      @occurrences ||= Array(template.recurring_month_occurrences(budget_month.month_on)).map(&:to_date).sort
    end

    def sort_previews(previews)
      previews.sort_by { |preview| [ preview[:occurred_on] || Date.new(9999, 12, 31), preview[:payee].to_s.downcase ] }
    end

    def unused_entry?(entry, used_entry_keys)
      !used_entry_keys.include?(entry_key(entry))
    end

    def entry_key(entry)
      entry.id || entry.object_id
    end

    def date_distance(entry_date, occurred_on)
      return 999_999 if entry_date.blank?

      (entry_date.to_date - occurred_on.to_date).abs
    end
  end
end
