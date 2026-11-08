require "json"

module Platform
  module MemoryDiagnostics
    REQUEST_SAMPLE_INTERVAL = 30
    GC_FIELDS = %i[heap_live_slots heap_allocated_pages old_objects total_allocated_objects major_gc_count minor_gc_count].freeze

    def self.record(source:, job_class: nil, force: false)
      return unless ENV["MEMORY_DIAGNOSTICS"] == "true"

      mutex.synchronize do
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return if !force && @last_sample_at && now - @last_sample_at < REQUEST_SAMPLE_INTERVAL

        @last_sample_at = now
        Rails.logger.info(JSON.generate(
          type: "memory_sample", timestamp: Time.current.utc.iso8601, pid: Process.pid,
          source: source, job_class: job_class, gc: GC.stat.slice(*GC_FIELDS),
          process: process_memory, cgroup: cgroup_memory
        ))
      end
    rescue StandardError
      # Opt-in diagnostics must never interrupt a request or financial job.
      nil
    end

    def self.process_memory
      status = read_optional("/proc/self/status")
      rollup = read_optional("/proc/self/smaps_rollup")
      {
        rss_bytes: kilobytes(status, "VmRSS"),
        swap_bytes: kilobytes(status, "VmSwap"),
        pss_bytes: kilobytes(rollup, "Pss")
      }
    end

    def self.cgroup_memory
      root = "/sys/fs/cgroup"
      stats = read_optional("#{root}/memory.stat").to_s.lines.to_h { |line| line.split.first(2) }
      events = read_optional("#{root}/memory.events").to_s.lines.to_h { |line| line.split.first(2) }
      {
        current_bytes: integer(read_optional("#{root}/memory.current")),
        peak_bytes: integer(read_optional("#{root}/memory.peak")),
        swap_bytes: integer(read_optional("#{root}/memory.swap.current")),
        anonymous_bytes: integer(stats["anon"]),
        file_bytes: integer(stats["file"]),
        oom_count: integer(events["oom"]),
        oom_kill_count: integer(events["oom_kill"])
      }
    end

    def self.read_optional(path)
      File.read(path, 64.kilobytes)
    rescue SystemCallError, IOError
      nil
    end

    def self.kilobytes(contents, field)
      value = contents.to_s[/^#{Regexp.escape(field)}:\s+(\d+) kB$/, 1]
      value.to_i * 1024 if value
    end

    def self.integer(value)
      Integer(value, exception: false) if value
    end

    def self.mutex
      @mutex ||= Mutex.new
    end

    private_class_method :mutex, :read_optional, :kilobytes, :integer
  end
end
