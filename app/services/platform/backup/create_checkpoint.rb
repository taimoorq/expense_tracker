require "digest"

module Platform
  module Backup
    class CreateCheckpoint
      RETENTION = 7.days

      def self.call(user:, scopes:)
        new(user: user, scopes: scopes).call
      end

      def initialize(user:, scopes:)
        @user = user
        @requested_scopes = Array(scopes).map(&:to_s) & Platform::UserDataExport::SCOPES
      end

      def call
        provisioned = Identity::PersonalWorkspaceProvisioner.call(user: user)
        @workspace = provisioned.workspace
        @membership = provisioned.membership
        payload, checkpoint_scopes = build_payload
        checksum = payload[:payload_checksum] || Digest::SHA256.hexdigest(Platform::CanonicalJson.dump(payload))
        existing = workspace.restore_checkpoints.available.find_by(
          payload_checksum: checksum,
          selected_scopes: checkpoint_scopes
        )
        return existing if existing
        generation_key = SecureRandom.uuid

        Platform::Operations::Executor.call(
          workspace: workspace,
          actor_membership: membership,
          operation_type: "create_restore_checkpoint",
          idempotency_key: "#{checksum}:#{generation_key}",
          request: { payload_checksum: checksum, scopes: checkpoint_scopes, generation_key: generation_key },
          redacted_parameters: { "format_version" => payload.fetch(:version), "scopes" => checkpoint_scopes },
          on_replay: ->(reference) { RestoreCheckpoint.find(reference.fetch("id")) }
        ) do |operation|
          checkpoint = workspace.restore_checkpoints.create!(
            actor_membership: membership,
            checkpoint_operation: operation,
            payload_format_version: payload.fetch(:version).to_s,
            payload_checksum: checksum,
            encryption_version: CheckpointCodec::VERSION,
            selected_scopes: checkpoint_scopes,
            result_counts: payload_counts(payload),
            encrypted_payload: CheckpointCodec.encode(payload),
            expires_at: Time.current + RETENTION
          )
          Audit::Recorder.call(
            workspace: workspace,
            actor_membership: membership,
            operation_run: operation,
            entity: checkpoint,
            action: "restore_checkpoint",
            changed_fields: %i[state selected_scopes payload_format_version expires_at]
          )
          Platform::Operations::Executor::Completion.new(
            value: checkpoint,
            result_counts: checkpoint.result_counts,
            result_reference: { "type" => "RestoreCheckpoint", "id" => checkpoint.id }
          )
        end.value
      end

      private

      attr_reader :membership, :requested_scopes, :user, :workspace

      def build_payload
        if workspace.target_reads_enabled?
          scopes = requested_scopes
          scopes |= Platform::Backup::V2::Preview::FINANCIAL_SCOPES if (scopes & Platform::Backup::V2::Preview::FINANCIAL_SCOPES).any?
          [ Platform::Backup::V2::Exporter.new(user: user, scopes: scopes).as_json, scopes ]
        else
          payload = ApplicationRecord.transaction(isolation: :repeatable_read) do
            Platform::UserDataExport.new(user: user, scopes: requested_scopes).as_json
          end
          [ payload, requested_scopes ]
        end
      end

      def payload_counts(payload)
        payload.fetch(:data, {}).each_with_object({}) do |(scope, value), counts|
          counts[scope.to_s] = count_records(value)
        end
      end

      def count_records(value)
        case value
        when Array then value.size
        when Hash then value.values.sum { |nested| count_records(nested) }
        else 0
        end
      end
    end
  end
end
