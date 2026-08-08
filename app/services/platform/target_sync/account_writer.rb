module Platform
  module TargetSync
    class AccountWriter
      MAPPING_VERSION = "target-live-v1".freeze

      def self.call(account:)
        new(account: account).call
      end

      def initialize(account:)
        @account = account
      end

      def call
        @context = Context.for(account)
        return if context.blank?

        Platform::Operations::Executor.call(
          workspace: workspace,
          actor_membership: membership,
          operation_type: "sync_legacy_account",
          idempotency_key: "legacy:Account:#{account.id}:#{account.lock_version}",
          request: source_attributes,
          redacted_parameters: { "legacy_record_type" => "Account", "legacy_record_id" => account.id },
          on_replay: ->(reference) { Account.find(reference.fetch("id")) }
        ) do |operation|
          mapping_store = TargetBackfill::MappingStore.new(
            workspace: workspace,
            operation_run: operation,
            version: MAPPING_VERSION
          )
          created = mapping_store.target_for(source: account, target_class: Account).blank?
          mapping_store.record!(source: account, target: account, source_attributes: source_attributes)
          Audit::Recorder.call(
            workspace: workspace,
            actor_membership: membership,
            operation_run: operation,
            entity: account,
            action: account.active? ? (created ? "create" : "edit") : "archive",
            changed_fields: account.previous_changes.keys - %w[created_at updated_at lock_version]
          )
          Platform::Operations::Executor::Completion.new(
            value: account,
            result_counts: { "accounts" => 1 },
            result_reference: { "type" => "Account", "id" => account.id }
          )
        end
      end

      private

      attr_reader :account, :context

      delegate :membership, :workspace, to: :context

      def source_attributes
        @source_attributes ||= account.attributes.except("created_at", "updated_at")
      end
    end
  end
end
