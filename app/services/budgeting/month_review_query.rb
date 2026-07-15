module Budgeting
  class MonthReviewQuery
    REASONS = %w[all due missing_details missing_actual auto_completed].freeze

    Result = Data.define(:selected_reason, :counts, :entries) do
      def active?
        selected_reason.present?
      end

      def count_for(reason)
        counts.fetch(reason.to_sym)
      end

      def issue_count
        counts.fetch(:all)
      end
    end

    def self.call(entries:, reason: nil, today: Date.current)
      new(entries: entries, reason: reason, today: today).call
    end

    def initialize(entries:, reason:, today:)
      @entries = Array(entries)
      @reason = reason.to_s.presence_in(REASONS)
      @today = today
    end

    def call
      matching_entries = {
        due: entries.select { |entry| due?(entry) },
        missing_details: entries.select { |entry| missing_details?(entry) },
        missing_actual: entries.select { |entry| missing_actual?(entry) },
        auto_completed: entries.select { |entry| auto_completed?(entry) }
      }
      all_entries = matching_entries.values.flatten.uniq { |entry| entry.id || entry.object_id }
      counts = matching_entries.transform_values(&:size).merge(all: matching_entries.values.sum(&:size))

      Result.new(
        selected_reason: reason,
        counts: counts,
        entries: selected_entries(matching_entries, all_entries)
      )
    end

    private

    attr_reader :entries, :reason, :today

    def selected_entries(matching_entries, all_entries)
      return [] unless reason.present?
      return all_entries if reason == "all"

      matching_entries.fetch(reason.to_sym)
    end

    def due?(entry)
      entry.planned? && entry.occurred_on.present? && entry.occurred_on <= today
    end

    def missing_details?(entry)
      entry.occurred_on.blank? || entry.category.blank? || entry.payee.blank?
    end

    def missing_actual?(entry)
      entry.paid? && entry.actual_amount.blank?
    end

    def auto_completed?(entry)
      return entry.auto_completed? if entry.respond_to?(:auto_completed?)

      entry.respond_to?(:auto_completed_at) && entry.auto_completed_at.present?
    end
  end
end
