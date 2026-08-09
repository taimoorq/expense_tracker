require "rails_helper"
require "active_job/continuation/test_helper"

RSpec.describe Platform::Backup::V2::ExportJob, type: :job do
  include ActiveJob::Continuation::TestHelper

  def dispatch(password: nil)
    user = create(:user)
    create(:account, user: user, name: "Private checking")
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    workspace.update!(target_writes_enabled: true, target_reads_enabled: true)
    result = Platform::Backup::V2::ExportDispatch.call(
      user: user,
      scopes: Platform::Backup::V2::Preview::FINANCIAL_SCOPES,
      password: password
    )
    clear_enqueued_jobs
    [ result.artifact, result.operation ]
  end

  it "generates a durable, encrypted-at-rest download artifact" do
    artifact, operation = dispatch

    described_class.perform_now(operation.id, artifact.id)

    expect(operation.reload).to have_attributes(state: "succeeded", progress_current: 3, progress_total: 3)
    expect(artifact.reload).to be_available
    expect(artifact.encrypted_contents).not_to include("Private checking")
    payload = JSON.parse(artifact.contents)
    expect(payload).to include("version" => 2, "payload_checksum" => match(/\A[0-9a-f]{64}\z/))
    expect(artifact.data_transfer_run.reload).to be_state_succeeded
  end

  it "uses and then clears an encrypted export password" do
    artifact, operation = dispatch(password: "very-secret")
    expect(artifact.encrypted_export_password).not_to include("very-secret")

    described_class.perform_now(operation.id, artifact.id)

    artifact.reload
    expect(artifact.encrypted_export_password).to be_nil
    decoded = Platform::UserDataBackupCodec.decode(source: artifact.contents, password: "very-secret")
    expect(decoded).to include(success: true, encrypted: true)
  end
end
