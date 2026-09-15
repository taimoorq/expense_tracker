class BackupSchedule < ApplicationRecord
  RETENTION_OPTIONS = [ 7, 14, 30 ].freeze

  enum :state, { enabled: "enabled", paused: "paused" }, prefix: true
  enum :cadence, { daily: "daily", weekly: "weekly", monthly: "monthly" }, prefix: true

  belongs_to :budget_workspace
  belongs_to :creator_membership, class_name: "WorkspaceMembership"
  has_many :backup_archives, dependent: :restrict_with_error

  validates :time_zone, inclusion: { in: ActiveSupport::TimeZone.all.map(&:name) }
  validates :local_minute_of_day, numericality: { only_integer: true, in: 0..1_439 }
  validates :retention_count, inclusion: { in: RETENTION_OPTIONS }
  validates :weekday, numericality: { only_integer: true, in: 0..6 }, if: :cadence_weekly?
  validates :day_of_month, numericality: { only_integer: true, in: 1..28 }, if: :cadence_monthly?
  validate :creator_belongs_to_workspace
  validate :cadence_fields_are_coherent
  validate :next_run_matches_state

  scope :due, ->(at = Time.current) { state_enabled.where(next_run_at: ..at) }

  def local_hour
    local_minute_of_day.div(60)
  end

  def local_minute
    local_minute_of_day % 60
  end

  def enable!(after: Time.current)
    update!(state: "enabled", next_run_at: Platform::Backup::ScheduleCalculator.next_at(self, after: after))
  end

  def pause!
    update!(state: "paused", next_run_at: nil)
  end

  private

  def creator_belongs_to_workspace
    return if creator_membership.blank? || creator_membership.budget_workspace_id == budget_workspace_id

    errors.add(:creator_membership, "must belong to the same workspace")
  end

  def cadence_fields_are_coherent
    errors.add(:weekday, "must be blank unless cadence is weekly") if !cadence_weekly? && weekday.present?
    errors.add(:weekday, "is required for weekly backups") if cadence_weekly? && weekday.blank?
    errors.add(:day_of_month, "must be blank unless cadence is monthly") if !cadence_monthly? && day_of_month.present?
    errors.add(:day_of_month, "is required for monthly backups") if cadence_monthly? && day_of_month.blank?
  end

  def next_run_matches_state
    return if state_enabled? == next_run_at.present?

    errors.add(:next_run_at, state_enabled? ? "is required when enabled" : "must be blank when paused")
  end
end
