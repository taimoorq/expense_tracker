module QueryCountHelper
  def count_select_queries
    count = 0
    callback = lambda do |_name, _started, _finished, _unique_id, payload|
      count += 1 if payload[:sql].to_s.match?(/\ASELECT/i) && payload[:name] != "SCHEMA"
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    count
  end
end

RSpec.configure do |config|
  config.include QueryCountHelper
end
