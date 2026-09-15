class BackupSchedulesController < ApplicationController
  include AutomaticBackupAccess

  def update
    workspace = automatic_backup_workspace!
    schedule = workspace.backup_schedule || workspace.build_backup_schedule(creator_membership: @automatic_backup_membership)
    attributes = normalized_schedule_params
    if attributes.fetch(:state) == "enabled"
      configuration = Platform::Backup::ArchiveConfiguration.current
      return redirect_to backup_restore_path, alert: configuration.error unless configuration.ready?
    end

    schedule.assign_attributes(attributes)
    schedule.next_run_at = schedule.state_enabled? ? Platform::Backup::ScheduleCalculator.next_at(schedule, after: Time.current) : nil
    schedule.save!
    Audit::Recorder.call(
      workspace: workspace,
      actor_membership: @automatic_backup_membership,
      operation_run: nil,
      entity: schedule,
      action: "edit",
      changed_fields: attributes.keys + [ :next_run_at ]
    )
    redirect_to backup_restore_path, notice: schedule.state_enabled? ? "Automatic backup schedule enabled." : "Automatic backup schedule paused."
  rescue ActiveRecord::RecordInvalid, ArgumentError => error
    redirect_to backup_restore_path, alert: "Automatic backup schedule could not be saved: #{error.message}"
  end

  def run_now
    automatic_backup_workspace!
    result = Platform::Backup::ArchiveDispatch.call(user: current_user)
    redirect_to operation_run_path(result.operation), notice: "Automatic backup queued. You can safely leave this page."
  rescue Platform::Backup::ArchiveDispatch::Unavailable,
    Platform::Backup::ArchiveDispatch::AlreadyInProgress => error
    redirect_to backup_restore_path, alert: error.message
  end

  private

  def normalized_schedule_params
    permitted = params.expect(backup_schedule: [
      :state,
      :cadence,
      :time_zone,
      :local_time,
      :weekday,
      :day_of_month,
      :retention_count,
      :lock_version
    ])
    cadence = permitted.fetch(:cadence)
    {
      state: permitted.fetch(:state),
      cadence: cadence,
      time_zone: permitted.fetch(:time_zone),
      local_minute_of_day: parse_local_time(permitted.fetch(:local_time)),
      weekday: cadence == "weekly" ? permitted[:weekday] : nil,
      day_of_month: cadence == "monthly" ? permitted[:day_of_month] : nil,
      retention_count: permitted.fetch(:retention_count),
      lock_version: permitted[:lock_version]
    }.compact
  end

  def parse_local_time(value)
    match = value.to_s.match(/\A(\d{2}):(\d{2})\z/)
    raise ArgumentError, "Choose a valid backup time." unless match

    hour = match[1].to_i
    minute = match[2].to_i
    raise ArgumentError, "Choose a valid backup time." unless hour.between?(0, 23) && minute.between?(0, 59)

    (hour * 60) + minute
  end
end
