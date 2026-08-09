require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module ExpenseTracker
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # This application does not accept image attachments. Keep Active Storage's
    # variant pipeline disabled instead of carrying native image dependencies.
    config.active_storage.variant_processor = :disabled

    config.generators do |generator|
      generator.orm :active_record, primary_key_type: :uuid
      generator.test_framework :rspec,
        fixtures: false,
        view_specs: false,
        helper_specs: false,
        routing_specs: false,
        request_specs: true,
        controller_specs: false,
        system_specs: true
      generator.fixture_replacement :factory_bot, dir: "spec/factories"
      generator.system_tests = nil
    end

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    config.active_record.deprecated_associations_options = { mode: :notify, backtrace: true }
    config.x.legacy_association_telemetry_enabled = ENV.fetch(
      "LEGACY_ASSOCIATION_TELEMETRY_ENABLED",
      Rails.env.production? ? "false" : "true"
    ).in?(%w[1 true yes])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
