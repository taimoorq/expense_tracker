require "rails_helper"

RSpec.describe Platform::OperationalEventLogSubscriber do
  it "writes one structured JSON log entry" do
    logger = instance_double(ActiveSupport::Logger)
    subscriber = described_class.new(logger: logger)
    event = {
      name: "finance_tracking.operation.succeeded",
      payload: { operation_id: "operation-id", result_count: 3 },
      context: { request_id: "request-id" },
      tags: {},
      timestamp: 123
    }

    expect(logger).to receive(:info) do |message|
      expect(JSON.parse(message)).to include(
        "type" => "operational_event",
        "name" => "finance_tracking.operation.succeeded",
        "payload" => { "operation_id" => "operation-id", "result_count" => 3 },
        "context" => { "request_id" => "request-id" }
      )
    end

    subscriber.emit(event)
  end
end
