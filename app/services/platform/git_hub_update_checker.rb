require "json"
require "net/http"

module Platform
  class GitHubUpdateChecker
    DEFAULT_REPOSITORY = "taimoorq/expense_tracker"
    DEFAULT_README_ANCHOR = "updating-a-self-hosted-install"
    CACHE_EXPIRY = 6.hours
    HTTP_TIMEOUT_SECONDS = 2
    DISABLED_VALUES = %w[false 0 no off].freeze

    Release = Struct.new(:version, :tag_name, :name, :html_url, :published_at, keyword_init: true) do
      def label
        "v#{version}"
      end
    end

    class << self
      def available_update
        release = latest_release
        return if release.blank?
        return unless newer_version?(release.version, Platform::ReleaseCatalog.current_version)

        release
      end

      def latest_release
        return unless enabled?

        Rails.cache.fetch(cache_key, expires_in: CACHE_EXPIRY, skip_nil: true) do
          fetch_latest_release
        end
      rescue StandardError => error
        Rails.logger.warn("GitHub release check failed: #{error.class}: #{error.message}")
        nil
      end

      def readme_update_url
        ENV["GITHUB_UPDATE_README_URL"].presence || "https://github.com/#{repository}##{DEFAULT_README_ANCHOR}"
      end

      def repository
        ENV["GITHUB_UPDATE_REPOSITORY"].presence || DEFAULT_REPOSITORY
      end

      def enabled?
        default = Rails.env.test? ? "false" : "true"
        !DISABLED_VALUES.include?(ENV.fetch("GITHUB_UPDATE_CHECKS_ENABLED", default).to_s.downcase)
      end

      def newer_version?(candidate_version, current_version)
        return false if candidate_version.blank? || current_version.blank?

        Gem::Version.new(normalized_version(candidate_version)) > Gem::Version.new(normalized_version(current_version))
      rescue ArgumentError
        normalized_version(candidate_version) != normalized_version(current_version)
      end

      private

      def fetch_latest_release
        response = http_client.request(github_request)
        return unless response.code.to_i == 200

        release_from_payload(JSON.parse(response.body))
      end

      def release_from_payload(payload)
        tag_name = payload.fetch("tag_name").to_s
        version = normalized_version(tag_name)
        return if version.blank?

        Release.new(
          version: version,
          tag_name: tag_name,
          name: payload["name"].to_s,
          html_url: payload["html_url"].to_s,
          published_at: payload["published_at"].to_s
        )
      end

      def github_request
        Net::HTTP::Get.new(github_latest_release_uri).tap do |request|
          request["Accept"] = "application/vnd.github+json"
          request["User-Agent"] = "ExpenseTracker/#{Platform::ReleaseCatalog.current_version || "unknown"}"
          request["Authorization"] = "Bearer #{github_token}" if github_token.present?
        end
      end

      def http_client
        Net::HTTP.new(github_latest_release_uri.hostname, github_latest_release_uri.port).tap do |http|
          http.use_ssl = true
          http.open_timeout = HTTP_TIMEOUT_SECONDS
          http.read_timeout = HTTP_TIMEOUT_SECONDS
        end
      end

      def github_latest_release_uri
        URI("https://api.github.com/repos/#{repository}/releases/latest")
      end

      def github_token
        ENV["GITHUB_UPDATE_TOKEN"].presence
      end

      def cache_key
        "platform/github_update_checker/#{repository}/latest_release/v1"
      end

      def normalized_version(version)
        version.to_s.strip.sub(/\Av/i, "")
      end
    end
  end
end
