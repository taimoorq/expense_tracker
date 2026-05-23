class ApplicationJob < ActiveJob::Base
  include Bullet::ActiveJob if defined?(Bullet::ActiveJob) && (Rails.env.development? || Rails.env.test?)

  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
end
