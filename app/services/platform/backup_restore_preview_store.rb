module Platform
  class BackupRestorePreviewStore
    DEFAULT_EXPIRATION = 15.minutes
    DEFAULT_STORE = ActiveSupport::Cache.lookup_store(:memory_store)

    def initialize(user:, store: DEFAULT_STORE, expires_in: DEFAULT_EXPIRATION)
      @user = user
      @store = store
      @expires_in = expires_in
    end

    def store(payload:, scopes:, encrypted:)
      token = SecureRandom.uuid
      @store.write(cache_key(token), { payload: payload, scopes: scopes, encrypted: encrypted }, expires_in: @expires_in)
      token
    end

    def load(token)
      return nil if token.blank?

      @store.read(cache_key(token))
    end

    def clear(token)
      return if token.blank?

      @store.delete(cache_key(token))
    end

    private

    attr_reader :user

    def cache_key(token)
      "backup_restore_preview:#{user.id}:#{token}"
    end
  end
end
