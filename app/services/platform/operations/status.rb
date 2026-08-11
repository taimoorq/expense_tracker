module Platform
  module Operations
    class Status
      VISIBLE_TYPES = {
        "backup_v2_restore" => [ "Backup restore", "Restoring the selected backup into this budget." ],
        "backup_v2_export" => [ "Backup export", "Building a consistent portable backup file." ],
        "commit_legacy_account_activity_import" => [ "Account activity import", "Saving the reviewed transaction rows." ],
        "reverse_import_batch" => [ "Import reversal", "Reversing transactions created by an import." ],
        "generate_budget_period" => [ "Month generation", "Creating planned items from recurring transactions." ],
        "close_budget_period" => [ "Month close", "Freezing a versioned month summary." ],
        "reopen_budget_period" => [ "Month reopen", "Reopening a closed month while retaining its prior close." ],
        "resolve_migration_missing_account" => [ "Account assignment", "Connecting a quarantined paid entry to the account you selected." ]
      }.freeze
      LIMIT = 5

      Result = Data.define(
        :id, :title, :description, :state, :state_label, :state_classes,
        :progress_percent, :progress_label, :result_summary, :error_label,
        :support_reference, :retryable, :started_at, :completed_at
      ) do
        def active?
          state.in?(%w[pending running])
        end
      end

      def self.recent(user:, limit: LIMIT)
        workspace = user.legacy_owned_budget_workspace
        return [] if workspace.blank?

        scope = workspace.operation_runs
          .where(operation_type: VISIBLE_TYPES.keys)
          .order(created_at: :desc)

        dismissed_through_at = workspace.workspace_memberships.find_by(user_id: user.id)&.recent_operations_dismissed_through_at
        if dismissed_through_at.present?
          scope = scope.where(
            "created_at > :dismissed_through_at OR state IN (:active_states)",
            dismissed_through_at: dismissed_through_at,
            active_states: %w[pending running]
          )
        end

        scope
          .limit(limit)
          .map { |operation| build(operation) }
      end

      def self.build(operation)
        title, description = VISIBLE_TYPES.fetch(operation.operation_type)
        Result.new(
          id: operation.id,
          title: title,
          description: description,
          state: operation.state,
          state_label: state_label(operation),
          state_classes: state_classes(operation),
          progress_percent: operation.progress_percent,
          progress_label: operation.progress_label.presence || default_progress_label(operation),
          result_summary: result_summary(operation.result_counts),
          error_label: error_label(operation.error_code),
          support_reference: operation.id.delete("-").first(12).upcase,
          retryable: operation.retryable?,
          started_at: operation.started_at,
          completed_at: operation.completed_at
        )
      end

      def self.visible_type?(operation_type)
        VISIBLE_TYPES.key?(operation_type)
      end

      def self.state_label(operation)
        {
          "pending" => "Waiting",
          "running" => "In progress",
          "succeeded" => "Complete",
          "failed" => "Needs attention",
          "reversed" => "Reversed"
        }.fetch(operation.state)
      end
      private_class_method :state_label

      def self.state_classes(operation)
        {
          "pending" => "bg-sky-100 text-sky-800",
          "running" => "bg-indigo-100 text-indigo-800",
          "succeeded" => "bg-emerald-100 text-emerald-800",
          "failed" => "bg-rose-100 text-rose-800",
          "reversed" => "bg-slate-100 text-slate-700"
        }.fetch(operation.state)
      end
      private_class_method :state_classes

      def self.default_progress_label(operation)
        return "Finished" if operation.state_succeeded?
        return "The operation stopped before it completed." if operation.state_failed?
        return "Safe to leave this page; status is saved." if operation.state_running?

        "Waiting to start"
      end
      private_class_method :default_progress_label

      def self.result_summary(counts)
        flattened = counts.each_with_object([]) do |(key, value), items|
          next unless value.is_a?(Numeric)

          items << "#{value} #{key.to_s.humanize(capitalize: false)}"
        end
        flattened.first(3).join(" · ").presence
      end
      private_class_method :result_summary

      def self.error_label(code)
        return if code.blank?

        "Reference this failure as #{code.to_s.humanize(capitalize: false)}."
      end
      private_class_method :error_label
    end
  end
end
