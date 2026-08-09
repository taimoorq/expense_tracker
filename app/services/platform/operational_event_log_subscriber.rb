require "json"

module Platform
  class OperationalEventLogSubscriber
    def initialize(logger: Rails.logger)
      @logger = logger
    end

    def emit(event)
      logger.info(
        JSON.generate(
          type: "operational_event",
          name: event.fetch(:name),
          payload: event.fetch(:payload),
          context: event.fetch(:context),
          tags: event.fetch(:tags),
          timestamp: event.fetch(:timestamp)
        )
      )
    end

    private

    attr_reader :logger
  end
end
