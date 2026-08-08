class LegacyRecordMapping < ApplicationRecord
  enum :status, {
    mapped: "mapped",
    omitted: "omitted",
    quarantined: "quarantined"
  }, prefix: true

  belongs_to :budget_workspace

  validates :legacy_record_type, :legacy_record_id, :target_record_type, :target_record_id, :mapping_version, presence: true
  validates :legacy_record_id,
    uniqueness: { scope: %i[budget_workspace_id legacy_record_type target_record_type] }
  validates :source_checksum, format: { with: /\A[0-9a-f]{64}\z/ }, allow_nil: true
end
