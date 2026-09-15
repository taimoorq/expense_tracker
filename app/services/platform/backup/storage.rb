module Platform
  module Backup
    module Storage
      Stat = Data.define(:key, :byte_size, :checksum)

      class Error < StandardError; end
      class Conflict < Error; end
      class InvalidKey < Error; end

      def self.build(configuration = ArchiveConfiguration.current)
        raise Error, configuration.error unless configuration.ready?

        case configuration.driver
        when ArchiveConfiguration::DRIVER_LOCAL
          Local.new(root: configuration.local_root)
        when ArchiveConfiguration::DRIVER_S3
          S3.new(
            bucket: configuration.s3_bucket,
            prefix: configuration.s3_prefix,
            region: configuration.s3_region,
            endpoint: configuration.s3_endpoint,
            force_path_style: configuration.s3_force_path_style?
          )
        else
          raise Error, "Unsupported backup storage driver"
        end
      end
    end
  end
end
