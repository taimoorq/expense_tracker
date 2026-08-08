require "json"

module Platform
  module TargetRelease
    class QueryPlanProbe
      EXECUTION_BUDGET_MS = 100

      PlanResult = Data.define(
        :name, :execution_time_ms, :planning_time_ms, :actual_rows, :node_types,
        :indexes, :shared_hit_blocks, :shared_read_blocks, :passed
      ) do
        def passed?
          passed
        end

        def as_json(*)
          {
            name: name,
            execution_time_ms: execution_time_ms,
            planning_time_ms: planning_time_ms,
            actual_rows: actual_rows,
            node_types: node_types,
            indexes: indexes,
            shared_hit_blocks: shared_hit_blocks,
            shared_read_blocks: shared_read_blocks,
            execution_budget_ms: EXECUTION_BUDGET_MS,
            passed: passed?
          }
        end
      end

      Result = Data.define(:workspace, :plans) do
        def passed?
          plans.all?(&:passed?)
        end

        def as_json(*)
          { workspace_id: workspace.id, passed: passed?, plans: plans.map(&:as_json) }
        end
      end

      Query = Data.define(:name, :sql)

      def self.call(workspace:)
        new(workspace: workspace).call
      end

      def initialize(workspace:)
        @workspace = workspace
        @connection = ActiveRecord::Base.connection
      end

      def call
        raise ArgumentError, "query-plan evidence requires PostgreSQL" unless connection.adapter_name == "PostgreSQL"

        Result.new(workspace: workspace, plans: queries.map { |query| explain(query) })
      end

      private

      attr_reader :connection, :workspace

      def explain(query)
        raw = connection.raw_connection.exec("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) #{query.sql}").getvalue(0, 0)
        document = raw.is_a?(String) ? JSON.parse(raw) : raw
        evidence = document.first
        root = evidence.fetch("Plan")
        nodes = flatten_nodes(root)
        execution_time = evidence.fetch("Execution Time").to_f.round(3)
        PlanResult.new(
          name: query.name,
          execution_time_ms: execution_time,
          planning_time_ms: evidence.fetch("Planning Time").to_f.round(3),
          actual_rows: root.fetch("Actual Rows", 0),
          node_types: nodes.map { |node| node["Node Type"] }.compact.uniq,
          indexes: nodes.map { |node| node["Index Name"] }.compact.uniq,
          shared_hit_blocks: root.fetch("Shared Hit Blocks", 0),
          shared_read_blocks: root.fetch("Shared Read Blocks", 0),
          passed: execution_time <= EXECUTION_BUDGET_MS
        )
      end

      def flatten_nodes(node)
        [ node ] + Array(node["Plans"]).flat_map { |child| flatten_nodes(child) }
      end

      def queries
        @queries ||= [
          Query.new("latest_account_observations", latest_account_observations_sql),
          Query.new("account_activity_timeline", account_activity_timeline_sql),
          Query.new("period_actual_totals", period_actual_totals_sql),
          Query.new("report_category_totals", report_category_totals_sql),
          Query.new("unmatched_activity", unmatched_activity_sql),
          Query.new("audit_timeline", audit_timeline_sql)
        ]
      end

      def latest_account_observations_sql
        <<~SQL.squish
          SELECT DISTINCT ON (account_id) id, account_id, balance, effective_through_at
          FROM balance_observations
          WHERE budget_workspace_id = #{quote(workspace.id)}
            AND account_id IN (#{quoted_ids(account_ids)})
            AND status = 'trusted'
            AND effective_through_at <= #{quote(as_of.end_of_day)}
          ORDER BY account_id, effective_through_at DESC, created_at DESC
        SQL
      end

      def account_activity_timeline_sql
        <<~SQL.squish
          SELECT financial_transactions.id, financial_transactions.effective_on,
            account_postings.amount, financial_transactions.description
          FROM account_postings
          INNER JOIN financial_transactions
            ON financial_transactions.id = account_postings.financial_transaction_id
          WHERE account_postings.budget_workspace_id = #{quote(workspace.id)}
            AND account_postings.account_id = #{quote(account_ids.first)}
            AND financial_transactions.state = 'posted'
            AND financial_transactions.effective_on <= #{quote(as_of)}
          ORDER BY financial_transactions.effective_on DESC,
            financial_transactions.created_at DESC
          LIMIT 100
        SQL
      end

      def period_actual_totals_sql
        <<~SQL.squish
          SELECT budget_items.budget_period_id, budget_items.flow_kind,
            SUM(budget_allocations.amount) AS total
          FROM budget_allocations
          INNER JOIN budget_items ON budget_items.id = budget_allocations.budget_item_id
          INNER JOIN financial_transactions
            ON financial_transactions.id = budget_allocations.financial_transaction_id
          WHERE budget_allocations.budget_workspace_id = #{quote(workspace.id)}
            AND budget_items.budget_period_id IN (#{quoted_ids(period_ids)})
            AND financial_transactions.state = 'posted'
          GROUP BY budget_items.budget_period_id, budget_items.flow_kind
        SQL
      end

      def report_category_totals_sql
        <<~SQL.squish
          SELECT COALESCE(categories.name, 'Uncategorized') AS category_name,
            SUM(financial_transactions.gross_amount) AS total
          FROM financial_transactions
          LEFT JOIN categories ON categories.id = financial_transactions.category_id
          WHERE financial_transactions.budget_workspace_id = #{quote(workspace.id)}
            AND financial_transactions.state = 'posted'
            AND financial_transactions.flow_kind = 'outflow'
            AND financial_transactions.effective_on BETWEEN #{quote(report_range.begin)} AND #{quote(report_range.end)}
          GROUP BY COALESCE(categories.name, 'Uncategorized')
          ORDER BY total DESC
          LIMIT 20
        SQL
      end

      def unmatched_activity_sql
        <<~SQL.squish
          SELECT financial_transactions.id, financial_transactions.effective_on
          FROM financial_transactions
          WHERE financial_transactions.budget_workspace_id = #{quote(workspace.id)}
            AND financial_transactions.state = 'posted'
            AND NOT EXISTS (
              SELECT 1 FROM budget_allocations
              WHERE budget_allocations.financial_transaction_id = financial_transactions.id
            )
          ORDER BY financial_transactions.effective_on DESC
          LIMIT 100
        SQL
      end

      def audit_timeline_sql
        <<~SQL.squish
          SELECT id, action, entity_type, entity_id, event_at
          FROM audit_events
          WHERE budget_workspace_id = #{quote(workspace.id)}
          ORDER BY event_at DESC, created_at DESC
          LIMIT 100
        SQL
      end

      def quote(value)
        connection.quote(value)
      end

      def quoted_ids(values)
        values.any? ? values.map { |value| quote(value) }.join(", ") : "NULL"
      end

      def account_ids
        @account_ids ||= workspace.accounts.limit(100).pluck(:id)
      end

      def period_ids
        @period_ids ||= workspace.budget_periods.order(starts_on: :desc).limit(12).pluck(:id)
      end

      def as_of
        @as_of ||= [ Date.current, workspace.budget_periods.maximum(:starts_on)&.end_of_month ].compact.max
      end

      def report_range
        @report_range ||= as_of.prev_year.next_day..as_of
      end
    end
  end
end
