module Platform
  module TargetTranslation
    class ExpenseEntry
      def self.call(entry:, workspace:, period:, category: nil)
        new(entry: entry, workspace: workspace, period: period, category: category).attributes
      end

      def initialize(entry:, workspace:, period:, category: nil)
        @entry = entry
        @workspace = workspace
        @period = period
        @category = category
      end

      def attributes
        {
          budget_workspace: workspace,
          budget_period: period,
          category: category,
          scheduled_on: entry.occurred_on,
          flow_kind: flow_kind,
          budget_group: budget_group,
          planned_amount: entry.planned_amount || 0,
          currency_code: workspace.default_currency_code,
          state: entry.skipped? ? "skipped" : "open",
          name_snapshot: entry.payee.presence || entry.category,
          payee_snapshot: entry.payee,
          category_snapshot: entry.category,
          intended_source_account: entry.source_account,
          intended_destination_account: entry.destination_account,
          priority_classification: priority_classification,
          origin_kind: origin_kind,
          notes: entry.notes
        }
      end

      def self.flow_kind(entry)
        return "income" if entry.income?
        return "transfer" if entry.source_account_id.present? && entry.destination_account_id.present?

        "outflow"
      end

      def self.budget_group(entry)
        return "fixed" if entry.fixed?
        return "variable" if entry.variable?
        return "debt" if entry.debt?

        "other"
      end

      def self.origin_kind(entry)
        return "recurring" if entry.generated_from_template?
        return "manual" if entry.manual_origin?

        "migration"
      end

      def self.priority_classification(value)
        normalized = value.to_s.strip.downcase
        return normalized if normalized.in?(%w[need want goal])

        "unclassified"
      end

      private

      attr_reader :category, :entry, :period, :workspace

      def flow_kind
        self.class.flow_kind(entry)
      end

      def budget_group
        self.class.budget_group(entry)
      end

      def origin_kind
        self.class.origin_kind(entry)
      end

      def priority_classification
        self.class.priority_classification(entry.need_or_want)
      end
    end
  end
end
