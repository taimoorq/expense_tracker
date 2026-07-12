module Accounts
  module ActivityImports
    class PreviewStore
      DEFAULT_EXPIRATION = 15.minutes

      def initialize(user:, store: nil, expires_in: DEFAULT_EXPIRATION)
        @user = user
        @store = store || default_store
        @expires_in = expires_in
      end

      def store(preview)
        token = SecureRandom.uuid
        @store.write(cache_key(token), preview, expires_in: @expires_in)
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
        "account_activity_import_preview:#{user.id}:#{token}"
      end

      def default_store
        return Rails.cache unless Rails.cache.is_a?(ActiveSupport::Cache::NullStore)

        self.class.null_store_fallback
      end

      def self.null_store_fallback
        @null_store_fallback ||= ActiveSupport::Cache.lookup_store(:memory_store)
      end
    end
  end
end
