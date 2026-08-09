module Platform
  module Operations
    module JobRegistry
      JOBS = {
        "Accounts::ActivityImports::CommitJob" => -> { Accounts::ActivityImports::CommitJob },
        "Platform::Backup::V2::RestoreJob" => -> { Platform::Backup::V2::RestoreJob },
        "Platform::Backup::V2::ExportJob" => -> { Platform::Backup::V2::ExportJob }
      }.freeze

      def self.fetch(job_class)
        JOBS.fetch(job_class).call
      rescue KeyError
        raise ArgumentError, "Unregistered operation job #{job_class.inspect}"
      end
    end
  end
end
