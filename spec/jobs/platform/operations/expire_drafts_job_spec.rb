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

  it "expires payloads without instantiating the drafts or artifacts" do
    records = create_expired_failures
    create_checkpoint(8.days.ago)
    artifact = records.last
    artifact.update!(state: "ready", failed_at: nil, ready_at: Time.current,
      encrypted_contents: "large stored payload" * 20_000, filename: "backup.json")
    instantiated = []
    subscriber = ->(_name, _start, _finish, _id, payload) { instantiated << payload.fetch(:class_name) }

    ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") do
      described_class.perform_now
    end

    expect(instantiated & (records.map { |record| record.class.name } + [ "RestoreCheckpoint" ])).to be_empty
    expect(artifact.reload).to be_state_expired
    expect(artifact.encrypted_contents).to be_nil
  end

  it "invalidates stale draft objects rather than allowing them to restore expired payloads" do
    draft = create_expired_failures.first
    version = draft.lock_version

    described_class.perform_now

    expect { draft.update!(state: "queued", failed_at: nil) }.to raise_error(ActiveRecord::StaleObjectError)
    expect(draft.reload.lock_version).to eq(version + 1)
    expect(draft.preview_payload).to eq({})
  end

  it "rechecks eligibility if a selected draft is queued before the expiry update" do
    draft = create_expired_failures.first
    changed = false
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      next if changed || !payload[:sql].start_with?('SELECT "account_activity_import_drafts"."id"')

      changed = true
      draft.update_columns(state: "queued", failed_at: nil, lock_version: draft.lock_version + 1)
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      described_class.perform_now
    end

    expect(changed).to eq(true)
    expect(draft.reload).to be_state_queued
    expect(draft.preview_payload).to be_present
  end

  it "bounds work per invocation and converges on the remaining backlog" do
    drafts = Array.new(3) { create_expired_failures.first }
    stub_const("#{described_class}::BATCH_SIZE", 1)
    stub_const("#{described_class}::MAX_BATCHES_PER_SCOPE", 2)

    described_class.perform_now

    expect(AccountActivityImportDraft.where(id: drafts).state_expired.count).to eq(2)
    described_class.perform_now
    expect(AccountActivityImportDraft.where(id: drafts).state_expired.count).to eq(3)
  end

  it "keeps unexpired and queued payloads" do
    current = create(:account_activity_import_draft)
    queued = create_expired_failures.first
    queued.update!(state: "queued", failed_at: nil)

    described_class.perform_now

    expect(current.reload).to be_state_previewed
    expect(current.preview_payload).to be_present
    expect(queued.reload).to be_state_queued
    expect(queued.preview_payload).to be_present
  end

  it "clears expired checkpoints without deleting audit references or rollback timestamps" do
    expired = create_checkpoint(8.days.ago)
    restored = create_checkpoint(9.days.ago)
    restored_at = 1.day.ago.change(usec: 0)
    restored.update!(state: "restored", restored_at: restored_at)
    current = create_checkpoint(Time.current)

    described_class.perform_now

    expect(expired.reload).to have_attributes(state: "expired", encrypted_payload: "")
    expect(expired).to be_valid
    expect(restored.reload).to have_attributes(state: "restored", restored_at: restored_at, encrypted_payload: "")
    expect(restored).to be_valid
    expect(current.reload).to be_available
    expect(current.encrypted_payload).to be_present
    expect(expired.checkpoint_operation).to be_present
  end

  it "protects an expired recovery checkpoint until its queued restore finishes" do
    checkpoint = create_checkpoint(8.days.ago)
    token = Platform::BackupRestorePreviewStore.new(user: checkpoint.actor_membership.user).store(
      payload: preference_payload, scopes: [ "preferences" ], encrypted: false
    )
    draft = Platform::BackupRestorePreviewStore.new(user: checkpoint.actor_membership.user).load_draft(token)
    draft.update!(restore_checkpoint: checkpoint, state: "queued")

    described_class.perform_now
    expect(checkpoint.reload).to be_state_ready
    expect(checkpoint.encrypted_payload).to be_present

    draft.consume!
    described_class.perform_now
    expect(checkpoint.reload).to have_attributes(state: "expired", encrypted_payload: "")
  end

  def create_checkpoint(at)
    travel_to(at) do
      Platform::Backup::CreateCheckpoint.call(user: create(:user), scopes: [ "preferences" ])
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
