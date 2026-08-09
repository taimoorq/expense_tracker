require "rails_helper"

RSpec.describe Platform::OperationalEvents do
  it "emits an allowlisted, namespaced event" do
    events = capture_rails_events do
      described_class.notify(
        "external_dependency.failed",
        dependency: "github",
        operation: "latest_release",
        error_class: "Timeout::Error"
      )
    end

    expect(events.sole).to include(
      name: "finance_tracking.external_dependency.failed",
      payload: {
        dependency: "github",
        operation: "latest_release",
        error_class: "Timeout::Error"
      }
    )
  end

  it "rejects unknown events and payload fields before they can leak" do
    expect do
      described_class.notify("unknown", workspace_id: SecureRandom.uuid)
    end.to raise_error(ArgumentError, /Unknown operational event/)

    expect do
      described_class.notify(
        "external_dependency.failed",
        dependency: "github",
        operation: "latest_release",
        error_class: "Timeout::Error",
        token: "must-not-escape"
      )
    end.to raise_error(ArgumentError, /Unexpected fields.*:token/)
  end
end
