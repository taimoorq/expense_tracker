require "digest"

module Platform
  class BackupRestorePreviewStore
    DEFAULT_EXPIRATION = 15.minutes

    def initialize(user:, expires_in: DEFAULT_EXPIRATION)
      @user = user
      @expires_in = expires_in
    end

    def store(payload:, scopes:, encrypted:)
      payload = payload.to_h.deep_symbolize_keys
      validation = Platform::UserDataImportPreview.new(payload: payload, scopes: scopes).call
      raise InvalidPreview, validation.fetch(:error) unless validation[:success]

      provisioned = Identity::PersonalWorkspaceProvisioner.call(user: user)
      token = SecureRandom.urlsafe_base64(32)
      user.backup_restore_drafts.create!(
        budget_workspace: provisioned.workspace,
        token_digest: token_digest(token),
        payload_checksum: payload[:payload_checksum].presence || Digest::SHA256.hexdigest(Platform::CanonicalJson.dump(payload)),
        payload_format_version: payload.fetch(:version).to_s,
        encrypted_payload: Platform::Backup::RestoreDraftCodec.encode(payload),
        selected_scopes: Array(scopes).map(&:to_s),
        validation_manifest: validation.fetch(:manifest, {}),
        source_encrypted: encrypted,
        expires_at: expires_in.from_now
      )
      token
    end

    def load(token)
      load_draft(token)&.preview_data
    end

    def load_draft(token)
      return if token.blank?

      draft = user.backup_restore_drafts.find_by(token_digest: token_digest(token))
      draft if draft&.dispatchable?
    end

    def clear(token)
      draft = load_draft(token)
      draft&.expire! if draft&.state_previewed?
    end

    private

    attr_reader :expires_in, :user

    def token_digest(token)
      Digest::SHA256.hexdigest(token.to_s)
    end

    class InvalidPreview < StandardError; end
  end
end
