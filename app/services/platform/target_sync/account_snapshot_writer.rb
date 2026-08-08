require "digest"

module Platform
  module TargetSync
    class AccountSnapshotWriter
      MAPPING_VERSION = "target-live-v1".freeze

      def self.call(snapshot:, action: :upsert)
        new(snapshot: snapshot, action: action).call
      end

      def initialize(snapshot:, action:)
        @snapshot = snapshot
        @action = action.to_sym
      end

      def call
        @context = Context.for(snapshot)
        return if context.blank?
        raise ArgumentError, "Unsupported snapshot sync action" unless action.in?(%i[upsert supersede])

        Platform::Operations::Executor.call(
          workspace: workspace,
          actor_membership: membership,
          operation_type: "sync_legacy_account_snapshot",
          idempotency_key: "legacy:AccountSnapshot:#{snapshot.id}:#{snapshot.lock_version}:#{action}",
          request: source_attributes.merge("sync_action" => action),
          redacted_parameters: { "legacy_record_type" => "AccountSnapshot", "legacy_record_id" => snapshot.id },
          on_replay: ->(reference) { BalanceObservation.find_by(id: reference["id"]) }
        ) do |operation|
          observation = action == :upsert ? replace_observation(operation) : supersede_observation(operation)
          Platform::Operations::Executor::Completion.new(
            value: observation,
            result_counts: { "balance_observations" => observation.present? ? 1 : 0 },
            result_reference: { "type" => "BalanceObservation", "id" => observation&.id }
          )
        end
      end

      private

      attr_reader :action, :context, :snapshot

      delegate :membership, :workspace, to: :context

      def replace_observation(operation)
        mapping = current_mapping
        prior = mapped_observation(mapping)
        supersede!(prior, operation) if prior.present?

        observation = BalanceObservation.create!(observation_attributes)
        persist_mapping(mapping, observation, prior)
        Audit::Recorder.call(
          workspace: workspace,
          actor_membership: membership,
          operation_run: operation,
          entity: observation,
          action: "trust_observation",
          changed_fields: observation_attributes.keys
        )
        observation
      end

      def supersede_observation(operation)
        mapping = current_mapping
        observation = mapped_observation(mapping)
        raise MissingMapping, "The balance snapshot has not been synchronized" if observation.blank?

        supersede!(observation, operation)
        mapping.update!(
          status: "omitted",
          mapping_version: MAPPING_VERSION,
          source_checksum: source_checksum,
          metadata: mapping.metadata.merge("deleted_at" => Time.current.iso8601)
        )
        observation
      end

      def supersede!(observation, operation)
        return if observation.status_superseded?

        observation.update!(status: "superseded")
        Audit::Recorder.call(
          workspace: workspace,
          actor_membership: membership,
          operation_run: operation,
          entity: observation,
          action: "supersede_observation",
          changed_fields: %i[status]
        )
      end

      def persist_mapping(mapping, observation, prior)
        mapping ||= LegacyRecordMapping.new(
          budget_workspace: workspace,
          legacy_record_type: "AccountSnapshot",
          legacy_record_id: snapshot.id,
          target_record_type: "BalanceObservation"
        )
        prior_ids = Array(mapping.metadata["prior_target_ids"])
        prior_ids << prior.id if prior.present?
        mapping.assign_attributes(
          target_record_id: observation.id,
          mapping_version: MAPPING_VERSION,
          source_checksum: source_checksum,
          status: "mapped",
          metadata: { "prior_target_ids" => prior_ids.uniq, "effective_through_convention" => "calendar_day_end" }
        )
        mapping.save!
      end

      def observation_attributes
        effective_at = snapshot.recorded_on.end_of_day
        {
          budget_workspace: workspace,
          account: snapshot.account,
          actor_membership: membership,
          observed_at: [ Time.current, effective_at ].max,
          effective_through_at: effective_at,
          balance: snapshot.balance,
          available_balance: snapshot.available_balance,
          currency_code: workspace.default_currency_code,
          source_kind: "manual",
          status: "trusted",
          notes: snapshot.notes
        }
      end

      def current_mapping
        LegacyRecordMapping.find_by(
          budget_workspace: workspace,
          legacy_record_type: "AccountSnapshot",
          legacy_record_id: snapshot.id,
          target_record_type: "BalanceObservation"
        )
      end

      def mapped_observation(mapping)
        BalanceObservation.find_by(id: mapping&.target_record_id)
      end

      def source_attributes
        @source_attributes ||= snapshot.attributes.except("created_at", "updated_at")
      end

      def source_checksum
        Digest::SHA256.hexdigest(Platform::CanonicalJson.dump(source_attributes))
      end

      class MissingMapping < WriteRejected; end
    end
  end
end
