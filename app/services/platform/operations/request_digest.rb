require "digest"

module Platform
  module Operations
    module RequestDigest
      def self.for(request)
        Digest::SHA256.hexdigest(Platform::CanonicalJson.dump(request))
      end
    end
  end
end
