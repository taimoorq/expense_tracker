module Platform
  module TargetRelease
    class Eligibility
      Result = Data.define(:workspace, :comparison_count)

      SHADOW_GATES = [
        Platform::ShadowReads::WorkspaceAccountBalanceMatrix,
        Platform::ShadowReads::WorkspaceBudgetPeriodMatrix,
        Platform::ShadowReads::WorkspaceAttentionMatrix,
        Platform::ShadowReads::WorkspaceRecurrenceMatrix,
        Platform::ShadowReads::WorkspaceCloseReadinessMatrix
      ].freeze

      def self.call(workspace:)
        new(workspace: workspace).call
      end

      def initialize(workspace:)
        @workspace = workspace
      end

      def call
        raise GateFailed, "The workspace does not have a legacy owner." if workspace.legacy_owner_user.blank?
        raise GateFailed, "Target backfill is incomplete." if workspace.target_backfilled_at.blank?
        raise GateFailed, "Open migration discrepancies block target reads." if workspace.migration_discrepancies.status_open.exists?

        results = SHADOW_GATES.map { |gate| gate.call(workspace: workspace, persist: false) }
        raise GateFailed, "A target shadow-read comparison failed." if results.any? { |result| !result.matched? }

        Result.new(
          workspace: workspace,
          comparison_count: results.sum { |result| result.comparisons.size }
        )
      end

      private

      attr_reader :workspace

      class GateFailed < StandardError; end
    end
  end
end
