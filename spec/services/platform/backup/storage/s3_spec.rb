require "rails_helper"

RSpec.describe Platform::Backup::Storage::S3 do
  let(:client) { Aws::S3::Client.new(stub_responses: true) }
  let(:storage) do
    described_class.new(
      bucket: "finance-tracking-backups",
      prefix: "local/archives",
      region: "us-east-1",
      client: client
    )
  end
  let(:contents) { "encrypted financial archive" }
  let(:checksum) { Digest::SHA256.hexdigest(contents) }
  let(:metadata) { { "sha256" => checksum } }

  it "publishes an immutable encrypted object and verifies its metadata" do
    client.stub_responses(:head_object, [ "NotFound", { content_length: contents.bytesize, metadata: metadata } ])
    client.stub_responses(:put_object, {})

    result = storage.write(key: "workspaces/one/archive.json", contents: contents, checksum: checksum)
    request = client.api_requests.find { |entry| entry[:operation_name] == :put_object }

    expect(result.checksum).to eq(checksum)
    expect(request[:params]).to include(
      bucket: "finance-tracking-backups",
      key: "local/archives/workspaces/one/archive.json",
      if_none_match: "*",
      server_side_encryption: "AES256",
      metadata: metadata
    )
  end

  it "reconciles an identical retry without another put" do
    client.stub_responses(:head_object, content_length: contents.bytesize, metadata: metadata)

    result = storage.write(key: "archive.json", contents: contents, checksum: checksum)

    expect(result.checksum).to eq(checksum)
    expect(client.api_requests.none? { |entry| entry[:operation_name] == :put_object }).to be(true)
  end

  it "reconciles an ambiguous conditional-write response by the stable object key" do
    response = Seahorse::Client::Http::Response.new(status_code: 412)
    context = Seahorse::Client::RequestContext.new(http_response: response)
    conditional_error = Aws::S3::Errors::ServiceError.new(context, "conditional request failed")
    client.stub_responses(:head_object, [ "NotFound", { content_length: contents.bytesize, metadata: metadata } ])
    allow(client).to receive(:put_object).and_raise(conditional_error)

    result = storage.write(key: "archive.json", contents: contents, checksum: checksum)

    expect(result.checksum).to eq(checksum)
  end

  it "refuses to replace an object with different content" do
    client.stub_responses(:head_object, content_length: 9, metadata: { "sha256" => "0" * 64 })

    expect do
      storage.write(key: "archive.json", contents: contents, checksum: checksum)
    end.to raise_error(Platform::Backup::Storage::Conflict)
  end

  it "reads and confirms deletion through the provider" do
    client.stub_responses(:get_object, body: contents)
    client.stub_responses(:delete_object, {})
    client.stub_responses(:head_object, "NotFound")

    expect(storage.read("archive.json")).to eq(contents)
    expect(storage.delete("archive.json")).to be(true)
  end

  it "rejects unsafe object keys" do
    expect { storage.read("../escape.json") }.to raise_error(Platform::Backup::Storage::InvalidKey)
    expect { storage.read("/absolute.json") }.to raise_error(Platform::Backup::Storage::InvalidKey)
  end
end
