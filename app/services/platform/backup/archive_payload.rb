require "digest"

module Platform
  module Backup
    class ArchivePayload
      class InvalidPayload < StandardError; end

      def self.export(user:, scopes:, version:)
        exporter = if version.to_i == V2::Exporter::FORMAT_VERSION
          V2::Exporter.new(user: user, scopes: scopes)
        elsif version.to_i == Platform::UserDataExport::FORMAT_VERSION
          Platform::UserDataExport.new(user: user, scopes: scopes)
        else
          raise InvalidPayload, "The requested archive format is not supported"
        end

        payload = exporter.as_json
        payload[:payload_checksum].present? ? payload : payload.merge(payload_checksum: checksum(payload))
      end

      def self.validate!(payload:, expected_version:, scopes:)
        version = payload.fetch(:version).to_i
        raise InvalidPayload, "The stored archive format changed" unless version == expected_version.to_i
        raise InvalidPayload, "The stored archive payload checksum changed" unless valid_checksum?(payload)

        return if version == Platform::UserDataExport::FORMAT_VERSION

        validation = V2::StagingValidator.new(payload: payload, scopes: scopes).call
        raise InvalidPayload, validation.fetch(:error) unless validation[:success]
      end

      def self.version_for(workspace)
        workspace.target_reads_enabled? ? V2::Exporter::FORMAT_VERSION : Platform::UserDataExport::FORMAT_VERSION
      end

      def self.valid_checksum?(payload)
        checksum(payload.except(:payload_checksum, "payload_checksum")) ==
          (payload[:payload_checksum] || payload["payload_checksum"])
      end

      def self.checksum(payload)
        Digest::SHA256.hexdigest(Platform::CanonicalJson.dump(payload))
      end

      private_class_method :checksum
    end
  end
end
