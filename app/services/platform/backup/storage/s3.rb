require "aws-sdk-s3"

module Platform
  module Backup
    module Storage
      class S3
        NOT_FOUND_CODES = [ "NoSuchKey", "NotFound", "NoSuchBucket" ].freeze
        CONFLICT_STATUSES = [ 409, 412 ].freeze

        def initialize(bucket:, prefix:, region:, endpoint: nil, force_path_style: false, client: nil)
          @bucket = bucket
          @prefix = prefix
          @client = client || Aws::S3::Client.new(
            region: region,
            endpoint: endpoint,
            force_path_style: force_path_style,
            retry_mode: "standard",
            max_attempts: 3
          )
        end

        def write(key:, contents:, checksum:)
          existing = stat(key)
          return reconcile(existing, checksum, contents.bytesize) if existing

          client.put_object(
            bucket: bucket,
            key: object_key(key),
            body: contents,
            content_type: "application/json; charset=utf-8",
            metadata: { "sha256" => checksum },
            server_side_encryption: "AES256",
            if_none_match: "*"
          )
          reconcile(stat(key), checksum, contents.bytesize)
        rescue Aws::S3::Errors::ServiceError => error
          return reconcile(stat(key), checksum, contents.bytesize) if conflict?(error)

          raise Error, storage_error_message(error)
        end

        def read(key)
          client.get_object(bucket: bucket, key: object_key(key)).body.read
        rescue Aws::S3::Errors::ServiceError => error
          return nil if not_found?(error)

          raise Error, storage_error_message(error)
        end

        def stat(key)
          response = client.head_object(bucket: bucket, key: object_key(key))
          Stat.new(
            key: key,
            byte_size: response.content_length,
            checksum: response.metadata["sha256"]
          )
        rescue Aws::S3::Errors::ServiceError => error
          return nil if not_found?(error)

          raise Error, storage_error_message(error)
        end

        def delete(key)
          client.delete_object(bucket: bucket, key: object_key(key))
          stat(key).nil?
        rescue Aws::S3::Errors::ServiceError => error
          raise Error, storage_error_message(error)
        end

        private

        attr_reader :bucket, :client, :prefix

        def object_key(key)
          parts = key.to_s.split("/")
          if key.blank? || key.start_with?("/") || parts.any? { |part| part.blank? || part == "." || part == ".." }
            raise InvalidKey, "Backup storage keys must be safe relative paths"
          end

          "#{prefix}/#{key}"
        end

        def reconcile(existing, checksum, byte_size)
          if existing&.checksum == checksum && existing.byte_size == byte_size
            return existing
          end

          raise Conflict, "A different archive already exists at the immutable storage key"
        end

        def conflict?(error)
          CONFLICT_STATUSES.include?(error.context.http_response.status_code)
        end

        def not_found?(error)
          error.context.http_response.status_code == 404 || NOT_FOUND_CODES.include?(error.code)
        end

        def storage_error_message(error)
          "S3 #{error.code}: #{error.message}"
        end
      end
    end
  end
end
