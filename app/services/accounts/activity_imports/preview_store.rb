require "digest"

module Accounts
  module ActivityImports
    class PreviewStore
      DEFAULT_EXPIRATION = 15.minutes

      def initialize(user:, expires_in: DEFAULT_EXPIRATION)
        @user = user
        @expires_in = expires_in
      end

      def store(preview)
        attributes = preview.deep_symbolize_keys
        account = user.accounts.find(attributes.fetch(:account_id))
        provisioned = ensure_workspace!(account)
        token = SecureRandom.urlsafe_base64(32)
        AccountActivityImportDraft.create!(
          user: user,
          account: account,
          budget_workspace: provisioned.workspace,
          token_digest: token_digest(token),
          commit_idempotency_key: attributes.fetch(:commit_idempotency_key),
          file_digest: attributes.fetch(:file_digest),
          rows_count: attributes.fetch(:rows_count),
          imported_count: attributes.fetch(:imported_count),
          duplicate_count: attributes.fetch(:duplicate_count),
          preview_payload: attributes.deep_stringify_keys,
          expires_at: @expires_in.from_now
        )
        token
      end

      def load(token)
        load_draft(token)&.preview
      end

      def load_draft(token)
        return if token.blank?

        draft = user.account_activity_import_drafts.find_by(token_digest: token_digest(token))
        draft if draft&.dispatchable?
      end

      def clear(token)
        draft = load_draft(token)
        draft&.expire! if draft&.state_previewed?
      end

      private

      attr_reader :expires_in, :user

      def ensure_workspace!(account)
        provisioned = Identity::PersonalWorkspaceProvisioner.call(user: user)
        account.update!(
          budget_workspace: provisioned.workspace,
          currency_code: provisioned.workspace.default_currency_code
        ) if account.budget_workspace_id.blank?
        provisioned
      end

      def token_digest(token)
        Digest::SHA256.hexdigest(token.to_s)
      end
    end
  end
end
