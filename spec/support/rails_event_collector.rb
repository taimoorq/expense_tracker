class RailsEventCollector
  attr_reader :events

  def initialize
    @events = []
  end

  def emit(event)
    events << event
  end
end

module RailsEventSpecHelper
  def capture_rails_events
    collector = RailsEventCollector.new
    Rails.event.subscribe(collector)
    yield
    collector.events
  ensure
    Rails.event.unsubscribe(collector) if collector
  end
end

RSpec.configure do |config|
  config.include RailsEventSpecHelper
end
