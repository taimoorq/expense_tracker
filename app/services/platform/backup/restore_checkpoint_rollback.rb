module Platform
  module Backup
    class RestoreCheckpointRollback
      def self.call(user:, checkpoint:)
        new(user: user, checkpoint: checkpoint).call
      end

      def initialize(user:, checkpoint:)
        @user = user
        @checkpoint = checkpoint
      end

      def call
        workspace = user.legacy_owned_budget_workspace
        membership = workspace&.workspace_memberships&.status_active&.find_by(user: user)
        Identity::WorkspaceAccess.authorize_write!(workspace: workspace, membership: membership)
        raise InvalidState, "This recovery checkpoint is no longer available." unless checkpoint.budget_workspace_id == workspace.id && checkpoint.available?

        checkpoint.with_lock do
          raise InvalidState, "This recovery checkpoint is no longer available." unless checkpoint.available?

          payload = CheckpointCodec.decode(checkpoint.encrypted_payload)
          validation = Platform::UserDataImportPreview.new(
            payload: payload,
            scopes: checkpoint.selected_scopes
          ).call
          raise InvalidState, validation.fetch(:error) unless validation[:success]

          Platform::UserDataImport.new(
            user: user,
            payload: payload,
            scopes: checkpoint.selected_scopes,
            replace_existing: true,
            checkpoint: checkpoint,
            rollback: true
          ).call
        end
      end

      private

      attr_reader :checkpoint, :user

      class InvalidState < StandardError; end
    end
  end
end
