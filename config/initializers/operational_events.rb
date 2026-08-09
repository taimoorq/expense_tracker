ActiveSupport::Notifications.subscribe("deprecated_association.active_record") do |_name, _started, _finished, _id, payload|
  reflection = payload.fetch(:reflection)
  location = payload[:location]
  source_location = location && "#{location.path}:#{location.lineno}"

  Platform::OperationalEvents.notify(
    "legacy_association.accessed",
    owner_type: reflection.active_record.name,
    association: reflection.name,
    source_location: source_location
  )
end

Rails.application.config.after_initialize do
  next if Rails.env.test?

  Rails.event.subscribe(Platform::OperationalEventLogSubscriber.new) do |event|
    event.fetch(:name).start_with?("finance_tracking.")
  end
end
