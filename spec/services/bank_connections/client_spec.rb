require "rails_helper"

RSpec.describe BankConnections::Simplefin::Client do
  subject(:client) { described_class.new }

  it "rejects untrusted hosts, plain HTTP, credentialed claims, nonstandard ports and arbitrary paths before networking" do
    expect(Net::HTTP).not_to receive(:new)
    [ "https://localhost/simplefin/claim/a", "https://bridge.simplefin.org.evil.test/simplefin/claim/a",
     "http://bridge.simplefin.org/simplefin/claim/a", "https://u:p@bridge.simplefin.org/simplefin/claim/a",
     "https://bridge.simplefin.org:8443/simplefin/claim/a", "https://bridge.simplefin.org/internal" ].each do |url|
      expect { client.claim(Base64.strict_encode64(url)) }.to raise_error(described_class::Error)
    end
  end

  it "rejects private DNS results and redacts the credential from failures" do
    allow(Resolv).to receive(:getaddresses).and_return([ "127.0.0.1" ])
    expect { client.accounts("https://user:never-show-this@bridge.simplefin.org/simplefin") }.to raise_error(described_class::Error) { |error|
      expect(error.message).to include("unsafe network")
      expect(error.inspect).not_to include("never-show-this")
    }
  end

  it "uses a pinned HTTPS address and Basic auth, with bounded timeouts and no redirects" do
    allow(Resolv).to receive(:getaddresses).and_return([ "93.184.216.34" ])
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:new).with("bridge.simplefin.org", 443, nil).and_return(http)
    { ipaddr: "93.184.216.34", use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_PEER, open_timeout: 5, read_timeout: 30, write_timeout: 10, max_retries: 0 }.each do |key, value|
      expect(http).to receive("#{key}=").with(value)
    end
    response = double(code: "302")
    allow(http).to receive(:start).and_yield(http)
    expect(http).to receive(:request) do |request, &block|
      expect(request.path).to include("version=2", "balances-only=1")
      expect(request["Authorization"]).to eq("Basic #{Base64.strict_encode64('user:secret')}")
      block.call(response)
    end
    expect { client.accounts("https://user:secret@bridge.simplefin.org/simplefin") }.to raise_error(described_class::Error, /Redirects are not followed/)
  end

  it "encrypts credentials and does not return them in model inspection" do
    connection = create(:bank_connection)
    expect(connection.encrypted_access_url).not_to include("private-test-token")
    expect(connection.access_url).to include("private-test-token")
    expect(connection.inspect).not_to include(connection.encrypted_access_url, "private-test-token")
  end
end
