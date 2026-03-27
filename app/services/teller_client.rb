require "net/http"
require "openssl"
require "json"

class TellerClient
  class Error < StandardError; end

  BASE_URL = "https://api.teller.io".freeze

  def initialize(access_token:)
    @access_token = access_token.to_s
  end

  def fetch_balances(account_id:)
    raise Error, "Teller access token is missing." if access_token.blank?
    raise Error, "Teller account ID is missing." if account_id.blank?
    raise Error, "Teller is not configured for this app." unless TellerConfiguration.enabled?

    request = Net::HTTP::Get.new("/accounts/#{account_id}/balances")
    request.basic_auth(access_token, "")
    response = perform_request(request)

    return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

    raise Error, "Teller balance request failed (#{response.code}): #{response.body.presence || response.message}"
  end

  private

  attr_reader :access_token

  def perform_request(request)
    uri = URI(BASE_URL)

    Net::HTTP.start(uri.host, uri.port, use_ssl: true, cert: certificate, key: private_key) do |http|
      http.request(request)
    end
  end

  def certificate
    @certificate ||= OpenSSL::X509::Certificate.new(File.read(TellerConfiguration.certificate_path))
  rescue Errno::ENOENT => error
    raise Error, "Teller certificate file could not be read: #{error.message}"
  end

  def private_key
    @private_key ||= OpenSSL::PKey.read(File.read(TellerConfiguration.private_key_path))
  rescue Errno::ENOENT => error
    raise Error, "Teller private key file could not be read: #{error.message}"
  end
end
