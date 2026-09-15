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

  it "gives local Solid Queue its own development database on the same server" do
    configured = with_database_environment do
      path = Rails.root.join("config/database.yml")
      yaml = ERB.new(path.read).result
      YAML.safe_load(yaml, aliases: true).fetch("development")
    end

    aggregate_failures do
      expect(configured.keys).to contain_exactly("primary", "queue")
      expect(configured.fetch("primary").fetch("database")).to eq("expense_tracker_development")
      expect(configured.fetch("queue")).to include(
        "database" => "expense_tracker_development_queue",
        "migrations_paths" => "db/queue_migrate",
        "host" => "db.internal"
      )
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
