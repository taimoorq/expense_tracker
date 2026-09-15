module Platform
  module Backup
    class DispatchDueSchedulesJob < ApplicationJob
      queue_as :maintenance

      BATCH_SIZE = 100

      def perform(now = Time.current)
        BackupSchedule.due(now).order(:next_run_at).limit(BATCH_SIZE).to_a.each do |schedule|
          dispatch_schedule(schedule, now)
        end
      end

      private

      def dispatch_schedule(schedule, now)
        scheduled_for = schedule.next_run_at
        return unless scheduled_for && scheduled_for <= now

        begin
          result = ArchiveDispatch.call(
            user: schedule.creator_membership.user,
            schedule: schedule,
            scheduled_for: scheduled_for
          )
          Platform::OperationalEvents.notify(
            "backup_schedule.dispatched",
            workspace_id: schedule.budget_workspace_id,
            schedule_id: schedule.id,
            archive_id: result.archive.id,
            scheduled_for: scheduled_for.iso8601
          )
          advance_schedule(schedule, scheduled_for, now)
        rescue ArchiveDispatch::AlreadyInProgress
          advance_schedule(schedule, scheduled_for, now)
        rescue StandardError => error
          record_failure(schedule, scheduled_for, now, error)
        end
      end

      def advance_schedule(schedule, scheduled_for, now)
        next_run = ScheduleCalculator.next_at(schedule, after: now)
        BackupSchedule
          .where(id: schedule.id, state: "enabled", next_run_at: scheduled_for)
          .update_all(
            next_run_at: next_run,
            last_attempted_at: now,
            updated_at: Time.current,
            lock_version: Arel.sql("lock_version + 1")
          )
      end

      def record_failure(schedule, scheduled_for, now, error)
        Rails.error.report(
          error,
          handled: true,
          context: { backup_schedule_id: schedule.id, workspace_id: schedule.budget_workspace_id }
        )
        next_run = ScheduleCalculator.next_at(schedule, after: now)
        BackupSchedule
          .where(id: schedule.id, state: "enabled", next_run_at: scheduled_for)
          .update_all(
            next_run_at: next_run,
            last_attempted_at: now,
            last_failed_at: now,
            last_error_code: error.class.name.underscore.tr("/", "_"),
            updated_at: Time.current,
            lock_version: Arel.sql("lock_version + 1")
          )
      end
    end
  end
end
