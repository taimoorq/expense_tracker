module Platform
  class ReleaseCatalog
    class << self
      def releases
        @releases ||= load_releases
      end

      def latest
        releases.first
      end

      def current_version
        latest&.version
      end

      def find(version)
        releases.find { |release| release.version == version.to_s }
      end

      def unread_for(user)
        return [] if user.blank?
        return releases if user.last_seen_release_version.blank?

        seen_index = releases.index { |release| release.version == user.last_seen_release_version }
        return releases if seen_index.nil?

        releases.first(seen_index)
      end

      def latest_unread_for(user)
        unread_for(user).first
      end

      def unread_count_for(user)
        unread_for(user).size
      end

      private

      def load_releases
        payload = YAML.safe_load_file(Rails.root.join("config/releases.yml"), permitted_classes: [], aliases: false) || {}

        Array(payload["releases"]).map do |entry|
          Platform::AppRelease.new(
            version: entry.fetch("version"),
            released_on: entry.fetch("released_on"),
            title: entry.fetch("title"),
            summary: entry.fetch("summary"),
            changes: entry.fetch("changes")
          )
        end
      end
    end
  end
end
