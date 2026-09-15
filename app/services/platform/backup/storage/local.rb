require "digest"
require "fileutils"
require "pathname"
require "securerandom"

module Platform
  module Backup
    module Storage
      class Local
        def initialize(root:)
          @root = Pathname.new(root).expand_path
        end

        def write(key:, contents:, checksum:)
          destination = path_for(key)
          existing = stat(key)
          return existing if existing&.checksum == checksum && existing.byte_size == contents.bytesize
          raise Conflict, "A different archive already exists at the immutable storage key" if existing

          FileUtils.mkdir_p(destination.dirname, mode: 0o700)
          File.chmod(0o700, destination.dirname)
          temporary = destination.dirname.join(".#{destination.basename}.#{SecureRandom.hex(8)}.tmp")
          begin
            File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
              file.write(contents)
              file.flush
              file.fsync
            end
            File.link(temporary, destination)
          rescue Errno::EEXIST
            existing = stat(key)
            return existing if existing&.checksum == checksum && existing.byte_size == contents.bytesize

            raise Conflict, "A different archive already exists at the immutable storage key"
          ensure
            FileUtils.rm_f(temporary)
          end

          stat(key).tap do |written|
            raise Error, "The archive could not be verified after writing" unless written&.checksum == checksum
          end
        rescue SystemCallError => error
          raise Error, error.message
        end

        def read(key)
          File.binread(path_for(key))
        rescue Errno::ENOENT
          nil
        rescue SystemCallError => error
          raise Error, error.message
        end

        def stat(key)
          path = path_for(key)
          return unless path.file?

          Stat.new(key: key, byte_size: path.size, checksum: Digest::SHA256.file(path).hexdigest)
        rescue SystemCallError => error
          raise Error, error.message
        end

        def delete(key)
          path = path_for(key)
          File.delete(path) if path.exist?
          !path.exist?
        rescue SystemCallError => error
          raise Error, error.message
        end

        private

        attr_reader :root

        def path_for(key)
          relative = Pathname.new(key.to_s)
          raise InvalidKey, "Backup storage keys must be relative" if relative.absolute?

          path = root.join(relative).cleanpath
          root_prefix = "#{root}#{File::SEPARATOR}"
          unless path.to_s.start_with?(root_prefix) && path != root
            raise InvalidKey, "Backup storage key escapes the configured root"
          end

          path
        end
      end
    end
  end
end
