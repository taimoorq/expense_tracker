class AppRelease
  attr_reader :version, :released_on, :title, :summary, :changes

  def initialize(version:, released_on:, title:, summary:, changes:)
    @version = version.to_s
    @released_on = Date.iso8601(released_on.to_s)
    @title = title.to_s
    @summary = summary.to_s
    @changes = Array(changes).map(&:to_s)
  end

  def label
    "v#{version}"
  end
end
