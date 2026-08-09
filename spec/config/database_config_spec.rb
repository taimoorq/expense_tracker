require "rails_helper"

RSpec.describe "production database configuration" do
  it "shares the configured server and credentials across primary, cache, and queue" do
    configured = with_database_environment do
      path = Rails.root.join("config/database.yml")
      yaml = ERB.new(path.read).result
      YAML.safe_load(yaml, aliases: true).fetch("production")
    end

    aggregate_failures do
      expect(configured.keys).to contain_exactly("primary", "cache", "queue")

      configured.each_value do |database|
        expect(database).to include(
          "host" => "db.internal",
          "port" => 5544,
          "username" => "application",
          "password" => "not-a-secret"
        )
      end
    end
  end

  def with_database_environment
    values = {
      "EXPENSE_TRACKER_DATABASE_HOST" => "db.internal",
      "EXPENSE_TRACKER_DATABASE_PORT" => "5544",
      "EXPENSE_TRACKER_DATABASE_USERNAME" => "application",
      "EXPENSE_TRACKER_DATABASE_PASSWORD" => "not-a-secret"
    }
    previous = values.keys.to_h { |key| [ key, ENV[key] ] }

    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end
end
