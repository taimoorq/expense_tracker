module Accounts
  module ActivityImports
    class History
      DEFAULT_LIMIT = 25

      Result = Data.define(
        :imports,
        :latest_import,
        :recommended_start_on,
        :overlap_count,
        :limited
      ) do
        def any?
          imports.any?
        end

        def overlap?
          overlap_count.positive?
        end

        def limited?
          limited
        end
      end

      def self.call(account:, candidate_starts_on: nil, candidate_ends_on: nil, limit: DEFAULT_LIMIT)
        new(
          account: account,
          candidate_starts_on: candidate_starts_on,
          candidate_ends_on: candidate_ends_on,
          limit: limit
        ).call
      end

      def initialize(account:, candidate_starts_on:, candidate_ends_on:, limit:)
        @account = account
        @candidate_starts_on = parse_date(candidate_starts_on)
        @candidate_ends_on = parse_date(candidate_ends_on)
        @limit = limit
      end

      def call
        imports = import_scope.limit(limit + 1).to_a
        latest_import = imports.first

        Result.new(
          imports: imports.first(limit),
          latest_import: latest_import,
          recommended_start_on: latest_import&.ended_on,
          overlap_count: overlap_count,
          limited: imports.size > limit
        )
      end

      private

      attr_reader :account, :candidate_ends_on, :candidate_starts_on, :limit

      def import_scope
        account.account_activity_imports.recent_first
      end

      def overlap_count
        return 0 if candidate_starts_on.blank? || candidate_ends_on.blank?

        import_scope
          .where.not(started_on: nil)
          .where.not(ended_on: nil)
          .where("started_on <= ? AND ended_on >= ?", candidate_ends_on, candidate_starts_on)
          .count
      end

      def parse_date(value)
        return value if value.is_a?(Date)
        return if value.blank?

        Date.parse(value.to_s)
      rescue Date::Error
        nil
      end
    end
  end
end
