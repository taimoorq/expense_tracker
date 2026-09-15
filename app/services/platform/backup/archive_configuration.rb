require "base64"
require "json"

module Platform
  module Backup
    class ArchiveConfiguration
      DRIVER_DISABLED = "disabled".freeze
      DRIVER_LOCAL = "local".freeze
      DRIVER_S3 = "s3".freeze

      def self.current
        new
      end

      def initialize(environment: ENV)
        @environment = environment
      end

      def driver
        environment.fetch("BACKUP_STORAGE_DRIVER", DRIVER_DISABLED).presence || DRIVER_DISABLED
      end

      def local_root
        Pathname.new(environment.fetch("BACKUP_LOCAL_ROOT", "/rails/backups"))
      end

      def primary_key_id
        environment.fetch("BACKUP_ENCRYPTION_KEY_ID", "primary")
      end

      def primary_key
        decode_key(environment["BACKUP_ENCRYPTION_KEY"])
      end

      def s3_bucket
        environment["BACKUP_S3_BUCKET"].to_s
      end

      def s3_prefix
        environment.fetch("BACKUP_S3_PREFIX", "finance-tracking/backups").to_s.sub(%r{\A/+}, "").sub(%r{/+\z}, "")
      end

      def s3_region
        environment["BACKUP_S3_REGION"].presence || environment["AWS_REGION"].presence || environment["AWS_DEFAULT_REGION"].presence
      end

      def s3_endpoint
        environment["BACKUP_S3_ENDPOINT"].presence
      end

      def s3_force_path_style?
        ActiveModel::Type::Boolean.new.cast(environment["BACKUP_S3_FORCE_PATH_STYLE"])
      end

      def key_for(key_id)
        keyring[key_id.to_s]
      end

      def keyring
        @keyring ||= previous_keyring.merge(primary_key_id => primary_key).compact
      end

      def ready?
        error.blank?
      end

      def error
        return "Automatic backup storage is not configured." if driver == DRIVER_DISABLED
        return "The configured backup storage driver is not supported." unless [ DRIVER_LOCAL, DRIVER_S3 ].include?(driver)
        return "The local backup path must be absolute." if driver == DRIVER_LOCAL && !local_root.absolute?
        return "An S3 backup bucket is required." if driver == DRIVER_S3 && s3_bucket.blank?
        return "An S3 backup region is required." if driver == DRIVER_S3 && s3_region.blank?
        return "The S3 backup prefix is invalid." if driver == DRIVER_S3 && invalid_s3_prefix?
        return "A backup encryption key ID is required." if primary_key_id.blank?
        return "A valid 32-byte backup encryption key is required." unless primary_key&.bytesize == 32
        return "Every previous backup encryption key must be a named 32-byte base64 value." if invalid_previous_keys?

        nil
      end

      def safe_label
        case driver
        when DRIVER_LOCAL then "Host-managed filesystem"
        when DRIVER_S3 then "S3-compatible object storage"
        else "Not configured"
        end
      end

      private

      attr_reader :environment

      def decode_key(value)
        return if value.blank?

        Base64.strict_decode64(value)
      rescue ArgumentError
        nil
      end

      def previous_keyring
        value = environment["BACKUP_ENCRYPTION_PREVIOUS_KEYS"]
        return {} if value.blank?

        JSON.parse(value).to_h.transform_values { |encoded| decode_key(encoded) }
      rescue JSON::ParserError, NoMethodError
        {}
      end

      def invalid_previous_keys?
        value = environment["BACKUP_ENCRYPTION_PREVIOUS_KEYS"]
        return false if value.blank?

        parsed = JSON.parse(value)
        return true unless parsed.is_a?(Hash) && parsed.keys.all?(&:present?)

        parsed.values.any? { |encoded| decode_key(encoded)&.bytesize != 32 }
      rescue JSON::ParserError
        true
      end

      def invalid_s3_prefix?
        s3_prefix.blank? || s3_prefix.split("/").any? { |part| part.blank? || part == "." || part == ".." }
      end
    end
  end
end
