require "base64"
require "net/http"
require "resolv"
require "ipaddr"

module BankConnections
  module Simplefin
    class Client
      HOSTS = %w[bridge.simplefin.org beta-bridge.simplefin.org].freeze
      MAX_BYTES = 10.megabytes
      BLOCKED_NETWORKS = %w[0.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 198.18.0.0/15 224.0.0.0/4 240.0.0.0/4 ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8].map { |value| IPAddr.new(value) }.freeze

      class Error < StandardError
        attr_reader :code
        def initialize(code, message)
          @code = code
          super(message)
        end
        def retryable?
          code == :temporary
        end
      end

      def claim(setup_token)
        raise Error.new(:invalid, "Enter a valid SimpleFIN Setup Token.") unless setup_token.to_s.bytesize.between?(1, 4096)
        uri = validated_uri(Base64.strict_decode64(setup_token.to_s.strip), claim: true)
        response = request(uri, method: :post)
        validated_uri(response.strip, claim: false).to_s
      rescue ArgumentError, URI::InvalidURIError
        raise Error.new(:invalid, "Enter a valid SimpleFIN Setup Token."), cause: nil
      end

      def accounts(access_url, transactions: false, start_at: nil)
        uri = validated_uri(access_url, claim: false)
        query = { "version" => "2" }
        if transactions
          query["start-date"] = (start_at || 30.days.ago).to_i
          query["end-date"] = Time.current.to_i
          query["pending"] = "1"
        else
          query["balances-only"] = "1"
        end
        uri.path = "#{uri.path}/accounts"
        uri.query = URI.encode_www_form(query)
        payload = JSON.parse(request(uri, method: :get))
        unless payload.is_a?(Hash) && payload["accounts"].is_a?(Array) && payload["accounts"].size <= 1000
          raise Error.new(:invalid_response, "SimpleFIN returned an invalid account response.")
        end
        payload
      rescue JSON::ParserError
        raise Error.new(:invalid_response, "SimpleFIN returned an unreadable response.")
      end

      private

      def validated_uri(value, claim:)
        uri = URI.parse(value.to_s)
        valid_path = claim ? uri.path.match?(%r{\A/simplefin/claim/[A-Za-z0-9_-]+\z}) : uri.path == "/simplefin"
        valid_auth = claim ? uri.userinfo.nil? : uri.user.present? && uri.password.present?
        unless uri.is_a?(URI::HTTPS) && HOSTS.include?(uri.host) && uri.port == 443 && uri.query.nil? && uri.fragment.nil? && valid_path && valid_auth
          raise Error.new(:invalid, "The token must use an official SimpleFIN Bridge endpoint.")
        end
        uri
      rescue URI::InvalidURIError
        raise Error.new(:invalid, "The SimpleFIN endpoint is invalid."), cause: nil
      end

      def public_address(host)
        addresses = Resolv.getaddresses(host)
        safe = addresses.present? && addresses.all? do |address|
          ip = IPAddr.new(address)
          !ip.private? && !ip.loopback? && !ip.link_local? && !ip.ipv4_mapped? && BLOCKED_NETWORKS.none? { |network| network.include?(ip) }
        end
        raise Error.new(:invalid, "SimpleFIN resolved to an unsafe network address.") unless safe
        addresses.first
      end

      def request(uri, method:)
        http = Net::HTTP.new(uri.host, uri.port, nil)
        http.ipaddr = public_address(uri.host) # Pin the checked address; TLS still verifies the hostname.
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.open_timeout = 5
        http.read_timeout = 30
        http.write_timeout = 10
        http.max_retries = 0
        request = method == :post ? Net::HTTP::Post.new(uri.request_uri) : Net::HTTP::Get.new(uri.request_uri)
        request["Content-Length"] = "0" if method == :post
        if uri.user
          request.basic_auth(URI::DEFAULT_PARSER.unescape(uri.user), URI::DEFAULT_PARSER.unescape(uri.password))
        end
        body = +""
        http.start do |session|
          session.request(request) do |response|
            handle_status(response.code.to_i, claim: method == :post)
            response.read_body do |chunk|
              body << chunk
              raise Error.new(:invalid_response, "The SimpleFIN response exceeded the supported size.") if body.bytesize > MAX_BYTES
            end
          end
        end
        body
      rescue Error
        raise
      rescue StandardError
        # HTTP exceptions can contain the credential-bearing URL or claim path.
        message = method == :post ? "The token claim could not be confirmed. Revoke that token in SimpleFIN and generate a new one before reconnecting." : "SimpleFIN could not be reached. Your last saved balances are unchanged."
        raise Error.new(method == :post ? :ambiguous_claim : :temporary, message), cause: nil
      end

      def handle_status(status, claim:)
        return if status == 200
        case status
        when 402 then raise Error.new(:payment, "Your SimpleFIN subscription needs attention. Check billing in SimpleFIN.")
        when 403
          message = claim ? "This Setup Token is invalid or already used. It may have been claimed elsewhere; revoke it in SimpleFIN and generate a new token." : "SimpleFIN access was revoked or is no longer valid. Reconnect with a new token."
          raise Error.new(:authentication, message)
        when 429 then raise Error.new(:rate_limit, "SimpleFIN's request limit was reached. Refresh is paused; try again later.")
        when 500..599 then raise Error.new(:temporary, "SimpleFIN is temporarily unavailable. Try again later.")
        else raise Error.new(:invalid_response, "SimpleFIN returned an unexpected response. Redirects are not followed.")
        end
      end
    end
  end
end
