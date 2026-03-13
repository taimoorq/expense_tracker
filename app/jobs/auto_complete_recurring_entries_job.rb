class AutoCompleteRecurringEntriesJob < ApplicationJob
  queue_as :default

  def perform(as_of: Date.current)
    AutoCompleteRecurringEntries.new(as_of: as_of).call
  end
end
