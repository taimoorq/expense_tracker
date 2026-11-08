require "rails_helper"
require "open3"

RSpec.describe "database payload logging" do
  it "keeps prepared binds enabled when the real development environment boots" do
    code = 'puts JSON.generate(disabled: ActiveRecord.disable_prepared_statements, tags: Rails.application.config.active_record.query_log_tags_enabled)'
    output, _error, status = Open3.capture3(
      { "RAILS_ENV" => "development", "SOLID_QUEUE_ENABLED" => "false", "MEMORY_DIAGNOSTICS" => "false" },
      RbConfig.ruby, "bin/rails", "runner", code, chdir: Rails.root.to_s
    )

    expect(status).to be_success
    expect(JSON.parse(output.lines.last)).to eq("disabled" => false, "tags" => false)
  end

  it "filters import payload binds from real debug SQL logs" do
    output = StringIO.new
    logger = ActiveSupport::Logger.new(output)
    logger.level = Logger::DEBUG
    previous = ActiveRecord::Base.logger
    ActiveRecord::Base.logger = logger

    draft = create(:account_activity_import_draft)
    draft.update!(preview_payload: draft.preview_payload.merge("private_marker" => "PRIVATE_IMPORT_PAYLOAD"))

    expect(output.string).to include("[FILTERED]")
    expect(output.string).not_to include("PRIVATE_IMPORT_PAYLOAD")
  ensure
    ActiveRecord::Base.logger = previous
  end

  it "filters backup and provider revision values through the SQL inspection filter" do
    %w[preview_payload raw_payload normalized_payload encrypted_payload encrypted_contents encrypted_export_password previous_revisions].each do |column|
      expect(ActiveRecord::Base.inspection_filter.filter_param(column, "PRIVATE_VALUE")).to eq("[FILTERED]")
    end
  end
end
