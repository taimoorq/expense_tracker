require "rails_helper"

RSpec.describe "job memory capacity configuration" do
  it "reserves a separate worker for maintenance without bypassing the heavy-job budget" do
    config = YAML.safe_load(ERB.new(Rails.root.join("config/queue.yml").read).result, aliases: true)

    %w[development production].each do |environment|
      workers = config.fetch(environment).fetch("workers")
      expect(workers.flat_map { |worker| worker.fetch("queues") }).not_to include("*")
      heavy = workers.select { |worker| (worker.fetch("queues") & %w[imports backups]).any? }
      expect(heavy.size).to eq(1)
      expect(heavy.sole).to include("queues" => %w[imports backups], "threads" => 1)
      expect(workers.find { |worker| worker.fetch("queues").include?("maintenance") })
        .to include("threads" => 1, "processes" => 1)
    end
  end

  it "routes application jobs and command-based recurring jobs to exactly one worker pool" do
    config = YAML.safe_load(ERB.new(Rails.root.join("config/queue.yml").read).result, aliases: true)
    queues = config.fetch("production").fetch("workers").flat_map { |worker| worker.fetch("queues") }
    job_queues = Rails.root.glob("app/jobs/**/*.rb").flat_map { |path| path.read.scan(/queue_as :(\w+)/).flatten }.uniq
    job_queues << SolidQueue::RecurringJob.queue_name

    job_queues.each { |queue| expect(queues.count(queue)).to eq(1) }
  end

  it "is consumed as separate serial pools by the installed Solid Queue configuration" do
    workers = SolidQueue::Configuration.new.configured_processes.select { |process| process.kind == :worker }

    expect(workers.size).to be >= 2
    expect(workers.map(&:attributes)).to include(
      include(queues: %w[imports backups], threads: 1),
      include(queues: %w[maintenance default mailers solid_queue_recurring], threads: 1)
    )
  end
end
