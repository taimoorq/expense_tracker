module Accounts
  class ActivityLedgerQuery
    SOURCES = %w[all institution_activity budget_entries].freeze
    DIRECTIONS = %w[all incoming outgoing].freeze
    DEFAULT_LIMIT = 150

    def initialize(account:, filters: {}, limit: DEFAULT_LIMIT)
      @account = account
      @user = account.user
      @filters = filters.to_h.with_indifferent_access
      @limit = limit
    end

    def call
      {
        source: source,
        direction: direction,
        merchant: merchant,
        classification: classification,
        starts_on: starts_on,
        ends_on: ends_on,
        institution_rows: institution_rows,
        budget_entries: budget_entry_rows,
        institution_net: institution_rows.sum { |row| row.account_delta.to_d },
        budget_net: budget_entry_rows.sum { |entry| impact_for(entry) }
      }
    end

    private

    attr_reader :account, :filters, :limit, :user

    def institution_rows
      return [] if source == "budget_entries"

      @institution_rows ||= begin
        scope = account.account_activities.includes(:account_activity_import).recent_first
        scope = scope.where(transaction_on: starts_on..) if starts_on
        scope = scope.where(transaction_on: ..ends_on) if ends_on
        rows = scope.to_a.select do |row|
          direction_matches?(row.account_delta.to_d) && merchant_matches?(row) && classification_matches?(row)
        end
        rows.first(limit)
      end
    end

    def budget_entry_rows
      return [] if source == "institution_activity"

      @budget_entry_rows ||= begin
        scope = user.expense_entries
          .where("source_account_id = :account_id OR destination_account_id = :account_id", account_id: account.id)
          .where.not(occurred_on: nil)
          .includes(:budget_month, :source_account, :destination_account, :source_template)
          .order(occurred_on: :desc, created_at: :desc)
        scope = scope.where(occurred_on: starts_on..) if starts_on
        scope = scope.where(occurred_on: ..ends_on) if ends_on
        rows = scope.limit(limit * 2).to_a.select { |entry| direction_matches?(impact_for(entry)) }
        rows.first(limit)
      end
    end

    def impact_for(entry)
      Accounts::EntryImpact.new(account: account, entry: entry).delta
    end

    def direction_matches?(delta)
      return delta.positive? if direction == "incoming"
      return delta.negative? if direction == "outgoing"

      true
    end

    def merchant_matches?(row)
      return true if merchant.blank?

      Accounts::ActivityInsights::MerchantNormalizer.call(row.description) == merchant
    end

    def classification_matches?(row)
      return true if classification.blank?

      Accounts::ActivityInsights::Classifier.call(row).to_s == classification
    end

    def source
      @source ||= filters[:source].to_s.in?(SOURCES) ? filters[:source].to_s : "all"
    end

    def direction
      @direction ||= filters[:direction].to_s.in?(DIRECTIONS) ? filters[:direction].to_s : "all"
    end

    def merchant
      @merchant ||= filters[:merchant].to_s.presence
    end

    def classification
      @classification ||= filters[:classification].to_s.in?(%w[interest fee payment credit charge neutral]) ? filters[:classification].to_s : nil
    end

    def starts_on
      @starts_on ||= parse_date(filters[:starts_on])
    end

    def ends_on
      @ends_on ||= parse_date(filters[:ends_on])
    end

    def parse_date(value)
      return if value.blank?

      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end
  end
end
