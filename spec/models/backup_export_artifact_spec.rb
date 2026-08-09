require "rails_helper"

RSpec.describe BackupExportArtifact do
  it "filters staged secrets and generated contents from inspection" do
    artifact = described_class.new(
      encrypted_export_password: "PRIVATE PASSWORD",
      encrypted_contents: "PRIVATE CONTENTS"
    )

    expect(artifact.inspect).not_to include("PRIVATE PASSWORD", "PRIVATE CONTENTS")
    expect(artifact.inspect).to include("[FILTERED]")
  end
end
