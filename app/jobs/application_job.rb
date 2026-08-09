class ApplicationJob < ActiveJob::Base
  include Bullet::ActiveJob if defined?(Bullet::ActiveJob) && (Rails.env.development? || Rails.env.test?)

  self.enqueue_after_transaction_commit = true

  before_perform do
    Rails.event.set_context(job_id: job_id, job_class: self.class.name)
  end

  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
end
