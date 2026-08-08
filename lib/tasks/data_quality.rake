require "json"

namespace :data_quality do
  desc "Report legacy financial-data violations without mutating records"
  task legacy: :environment do
    report = Platform::LegacyDataQualityReport.call(
      sample_limit: ENV.fetch("SAMPLE_LIMIT", Platform::LegacyDataQualityReport::DEFAULT_SAMPLE_LIMIT)
    )

    puts JSON.pretty_generate(report.as_json)

    if ENV["FAIL_ON_VIOLATIONS"] == "1" && !report.clean?
      abort "Legacy data-quality violations found."
    end
  end

  desc "Preview or apply deterministic durable keys for legacy generated entries"
  task repair_generated_entry_keys: :environment do
    result = Platform::LegacyGeneratedEntryKeyRepair.call(
      apply: ENV["APPLY"] == "1",
      batch_size: ENV.fetch("BATCH_SIZE", Platform::LegacyGeneratedEntryKeyRepair::DEFAULT_BATCH_SIZE).to_i,
      sample_limit: ENV.fetch("SAMPLE_LIMIT", Platform::LegacyGeneratedEntryKeyRepair::DEFAULT_SAMPLE_LIMIT).to_i
    )

    puts JSON.pretty_generate(result.as_json)
    abort("Generated-entry key repair has unresolved rows.") if ENV["FAIL_ON_UNRESOLVED"] == "1" && !result.clean?
  end
end
