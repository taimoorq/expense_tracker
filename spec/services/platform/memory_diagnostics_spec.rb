require "rails_helper"

RSpec.describe Platform::MemoryDiagnostics do
  around do |example|
    previous = ENV["MEMORY_DIAGNOSTICS"]
    ENV["MEMORY_DIAGNOSTICS"] = "true"
    example.run
  ensure
    ENV["MEMORY_DIAGNOSTICS"] = previous
  end

  it "logs numeric memory and GC counters without job arguments or finance payloads" do
    output = []
    allow(Rails.logger).to receive(:info) { |line| output << JSON.parse(line) }

    described_class.record(source: "job.started", job_class: "ExampleJob", force: true)

    expect(output.sole).to include("type" => "memory_sample", "pid" => Process.pid,
      "source" => "job.started", "job_class" => "ExampleJob")
    expect(output.sole.fetch("gc")).to include("heap_live_slots" => be_a(Integer))
    expect(output.sole.keys).not_to include("arguments", "payload", "user_id")
  end

  it "does no sampling when disabled" do
    ENV["MEMORY_DIAGNOSTICS"] = "false"
    expect(GC).not_to receive(:stat)
    expect(Rails.logger).not_to receive(:info)

    described_class.record(source: "request")
  end

  it "limits request sampling" do
    allow(Rails.logger).to receive(:info)
    described_class.record(source: "request", force: true)
    expect(Rails.logger).not_to receive(:info)
    described_class.record(source: "request")
  end

  it "remains harmless if logging fails" do
    allow(Rails.logger).to receive(:info).and_raise(IOError)
    expect { described_class.record(source: "job.finished", force: true) }.not_to raise_error
  end

  it "reports Linux process memory separately from cgroup cache and OOM counters" do
    allow(File).to receive(:read).and_call_original
    files = {
      "/proc/self/status" => "VmRSS:\t1024 kB\nVmSwap:\t2 kB\n",
      "/proc/self/smaps_rollup" => "Pss: 768 kB\n",
      "/sys/fs/cgroup/memory.stat" => "anon 900000\nfile 50000\n",
      "/sys/fs/cgroup/memory.events" => "oom 2\noom_kill 1\n",
      "/sys/fs/cgroup/memory.current" => "950000\n",
      "/sys/fs/cgroup/memory.peak" => "1200000\n",
      "/sys/fs/cgroup/memory.swap.current" => "2048\n"
    }
    files.each { |path, contents| allow(File).to receive(:read).with(path, 64.kilobytes).and_return(contents) }

    expect(described_class.process_memory).to eq(rss_bytes: 1_048_576, pss_bytes: 786_432, swap_bytes: 2048)
    expect(described_class.cgroup_memory).to include(current_bytes: 950_000,
      anonymous_bytes: 900_000, file_bytes: 50_000, oom_count: 2, oom_kill_count: 1)
  end

  it "samples the actual job process on success and failure" do
    job_class = Class.new(ApplicationJob) do
      def perform(fail_job = false)
        raise "test failure" if fail_job
      end
    end
    stub_const("MemorySampleJob", job_class)
    expect(described_class).to receive(:record).with(source: "job.started", job_class: "MemorySampleJob", force: true).twice
    expect(described_class).to receive(:record).with(source: "job.finished", job_class: "MemorySampleJob", force: true).twice

    job_class.perform_now
    expect { job_class.perform_now(true) }.to raise_error("test failure")
  end
end
