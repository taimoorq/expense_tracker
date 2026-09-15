require "rails_helper"
require "tmpdir"

RSpec.describe Platform::Backup::Storage::Local do
  around do |example|
    Dir.mktmpdir("finance-tracking-backups") do |directory|
      @directory = directory
      example.run
    end
  end

  let(:storage) { described_class.new(root: @directory) }
  let(:contents) { "encrypted financial archive" }
  let(:checksum) { Digest::SHA256.hexdigest(contents) }

  it "publishes an immutable archive and reconciles an identical retry" do
    first = storage.write(key: "workspaces/one/archive.json", contents: contents, checksum: checksum)
    second = storage.write(key: "workspaces/one/archive.json", contents: contents, checksum: checksum)

    expect(first).to eq(second)
    expect(storage.read("workspaces/one/archive.json")).to eq(contents)
    expect(File.stat(File.join(@directory, "workspaces/one/archive.json")).mode & 0o777).to eq(0o600)
  end

  it "refuses to overwrite a different archive" do
    storage.write(key: "archive.json", contents: contents, checksum: checksum)

    expect do
      storage.write(
        key: "archive.json",
        contents: "different",
        checksum: Digest::SHA256.hexdigest("different")
      )
    end.to raise_error(Platform::Backup::Storage::Conflict)
  end

  it "contains generated keys beneath the configured root" do
    expect { storage.read("../escape.json") }.to raise_error(Platform::Backup::Storage::InvalidKey)
    expect { storage.read("/absolute.json") }.to raise_error(Platform::Backup::Storage::InvalidKey)
  end

  it "confirms deletion" do
    storage.write(key: "archive.json", contents: contents, checksum: checksum)

    expect(storage.delete("archive.json")).to be(true)
    expect(storage.stat("archive.json")).to be_nil
  end
end
