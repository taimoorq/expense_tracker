module Platform
  module TargetRelease
    class ReversibleReadWindow
      def self.call(workspace:, &block)
        new(workspace: workspace).call(&block)
      end

      def initialize(workspace:)
        @workspace = workspace
        @original_writes = workspace.target_writes_enabled?
        @original_reads = workspace.target_reads_enabled?
      end

      def call
        enable!
        yield
      ensure
        restore!
      end

      def restored?
        workspace.reload
        workspace.target_writes_enabled? == original_writes &&
          workspace.target_reads_enabled? == original_reads
      end

      private

      attr_reader :original_reads, :original_writes, :workspace

      def enable!
        workspace.update!(target_writes_enabled: true) unless workspace.target_writes_enabled?
        workspace.update!(target_reads_enabled: true) unless workspace.target_reads_enabled?
      end

      def restore!
        workspace.reload
        workspace.update!(target_reads_enabled: false) if workspace.target_reads_enabled?
        workspace.update!(target_writes_enabled: original_writes) if workspace.target_writes_enabled? != original_writes
        workspace.update!(target_reads_enabled: true) if original_reads
      end
    end
  end
end
