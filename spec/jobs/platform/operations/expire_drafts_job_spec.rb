require "rails_helper"

RSpec.describe Platform::Operations::ExpireDraftsJob, type: :job do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  it "expires failed staged data and clears retained payloads" do
    activity_draft, restore_draft, export_artifact = create_expired_failures

    expect(activity_draft).not_to be_dispatchable
    expect(restore_draft).not_to be_dispatchable

    described_class.perform_now

    aggregate_failures do
      expect(activity_draft.reload).to be_state_expired
      expect(activity_draft.preview_payload).to eq({})
      expect(activity_draft.failed_at).to be_nil

      expect(restore_draft.reload).to be_state_expired
      expect(restore_draft.encrypted_payload).to be_empty
      expect(restore_draft.failed_at).to be_nil

      expect(export_artifact.reload).to be_state_expired
      expect(export_artifact.encrypted_contents).to be_nil
      expect(export_artifact.failed_at).to be_nil
    end
  end

  def create_expired_failures
    records = nil
    travel_to(2.days.ago) do
      activity_draft = create(:account_activity_import_draft)
      activity_draft.fail!

      restore_user = create(:user)
      token = Platform::BackupRestorePreviewStore.new(user: restore_user).store(
        payload: preference_payload,
        scopes: [ "preferences" ],
        encrypted: false
      )
      restore_draft = Platform::BackupRestorePreviewStore.new(user: restore_user).load_draft(token)
      restore_draft.fail!

      export_user = create(:user)
      create(:account, user: export_user)
      Platform::TargetBackfill::Runner.call(user: export_user)
      export_artifact = Platform::Backup::V2::ExportDispatch.call(
        user: export_user,
        scopes: [ "accounts" ]
      ).artifact
      export_artifact.fail!
      clear_enqueued_jobs

      records = [ activity_draft, restore_draft, export_artifact ]
    end
    records
  end

  def preference_payload
    {
      format: Platform::UserDataExport::FORMAT_NAME,
      version: 1,
      data: { preferences: { default_landing_page: "accounts" } }
    }
  end
end
