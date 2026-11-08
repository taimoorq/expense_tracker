ActiveSupport::Notifications.subscribe("process_action.action_controller") do
  Platform::MemoryDiagnostics.record(source: "request")
end
