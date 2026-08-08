require "set"

module Platform
  class LegacyGeneratedEntryKeyRepair
    Result = Data.define(
      :apply,
      :candidate_count,
      :repairable_count,
      :repaired_count,
      :conflict_count,
      :unsupported_count,
      :conflict_samples,
      :unsupported_samples
    ) do
      def clean?
        conflict_count.zero? && unsupported_count.zero?
      end

      def as_json(*)
        {
          apply: apply,
          clean: clean?,
          candidate_count: candidate_count,
          repairable_count: repairable_count,
          repaired_count: repaired_count,
          conflict_count: conflict_count,
          unsupported_count: unsupported_count,
          conflict_samples: conflict_samples,
          unsupported_samples: unsupported_samples
        }
      end
    end

    SOURCE_FILES = %w[pay_schedule subscription monthly_bill payment_plan credit_card_estimate].freeze
    DEFAULT_BATCH_SIZE = 500
    DEFAULT_SAMPLE_LIMIT = 10

    def self.call(apply: false, batch_size: DEFAULT_BATCH_SIZE, sample_limit: DEFAULT_SAMPLE_LIMIT)
      new(apply: apply, batch_size: batch_size, sample_limit: sample_limit).call
    end

    def initialize(apply:, batch_size:, sample_limit:)
      raise ArgumentError, "batch_size must be positive" unless batch_size.to_i.positive?
      raise ArgumentError, "sample_limit must be positive" unless sample_limit.to_i.positive?

      @apply = apply
      @batch_size = batch_size.to_i
      @sample_limit = sample_limit.to_i
      @seen_keys = Set.new
      @counts = Hash.new(0)
      @conflict_samples = []
      @unsupported_samples = []
    end

    def call
      candidate_scope.find_in_batches(batch_size: batch_size) do |entries|
        process_batch(entries)
      end

      Result.new(
        apply: apply,
        candidate_count: counts[:candidate],
        repairable_count: counts[:repairable],
        repaired_count: counts[:repaired],
        conflict_count: counts[:conflict],
        unsupported_count: counts[:unsupported],
        conflict_samples: conflict_samples,
        unsupported_samples: unsupported_samples
      )
    end

    private

    attr_reader :apply, :batch_size, :conflict_samples, :counts, :sample_limit,
      :seen_keys, :unsupported_samples

    def candidate_scope
      ExpenseEntry
        .where(generated_entry_key: nil, source_file: SOURCE_FILES)
        .where.not(source_template_id: nil)
        .includes(:budget_month, :source_template)
        .order(:id)
    end

    def process_batch(entries)
      entries_with_keys = entries.to_h { |entry| [ entry, entry.canonical_generated_entry_key ] }
      existing_keys = ExpenseEntry
        .where(generated_entry_key: entries_with_keys.values.compact)
        .pluck(:generated_entry_key)
        .to_set

      entries_with_keys.each do |entry, generated_key|
        process(entry, generated_key, existing_keys)
      end
    end

    def process(entry, generated_key, existing_keys)
      counts[:candidate] += 1
      return record_unsupported(entry, "canonical key cannot be derived") if generated_key.blank?
      return record_conflict(entry, generated_key) if key_conflict?(generated_key, existing_keys)

      counts[:repairable] += 1
      seen_keys.add(generated_key)
      return unless apply

      updated = ExpenseEntry.where(id: entry.id, generated_entry_key: nil).update_all(generated_entry_key: generated_key)
      counts[:repaired] += updated
    rescue ActiveRecord::RecordNotUnique
      counts[:repairable] -= 1
      record_conflict(entry, generated_key)
    end

    def key_conflict?(generated_key, existing_keys)
      seen_keys.include?(generated_key) || existing_keys.include?(generated_key)
    end

    def record_conflict(entry, generated_key)
      counts[:conflict] += 1
      return if conflict_samples.size >= sample_limit

      conflict_samples << { entry_id: entry.id, generated_entry_key: generated_key }
    end

    def record_unsupported(entry, reason)
      counts[:unsupported] += 1
      return if unsupported_samples.size >= sample_limit

      unsupported_samples << { entry_id: entry.id, reason: reason }
    end
  end
end
