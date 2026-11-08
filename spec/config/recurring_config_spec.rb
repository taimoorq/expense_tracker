require "rails_helper"

RSpec.describe "recurring maintenance configuration" do
  it "clears expired payloads and finished jobs in both long-lived environments" do
    configured = YAML.safe_load(Rails.root.join("config/recurring.yml").read)

    %w[development production].each do |environment|
      tasks = configured.fetch(environment)
      expect(tasks.fetch("expire_staged_operation_drafts")).to include(
        "class" => "Platform::Operations::ExpireDraftsJob",
        "queue" => "maintenance",
        "schedule" => "every 10 minutes"
      )
      expect(tasks.fetch("clear_solid_queue_finished_jobs").fetch("command"))
        .to eq("SolidQueue::Job.clear_finished_in_batches(sleep_between_batches: 0.3)")
    end
  end
end
