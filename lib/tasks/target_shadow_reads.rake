namespace :target_shadow_reads do
  desc "Compare legacy and target account balances without printing financial values"
  task account_balances: :environment do
    results = BudgetWorkspace.where.not(target_backfilled_at: nil).find_each.map do |workspace|
      Platform::ShadowReads::WorkspaceAccountBalanceMatrix.call(workspace: workspace).as_json
    end
    puts JSON.pretty_generate(results: results)
    abort "Target account balance shadow reads found mismatches" if results.any? { |result| !result.fetch(:matched) }
  end

  desc "Compare legacy and target period summaries without printing financial values"
  task budget_periods: :environment do
    results = BudgetWorkspace.where.not(target_backfilled_at: nil).find_each.map do |workspace|
      Platform::ShadowReads::WorkspaceBudgetPeriodMatrix.call(workspace: workspace).as_json
    end
    puts JSON.pretty_generate(results: results)
    abort "Target budget period shadow reads found mismatches" if results.any? { |result| !result.fetch(:matched) }
  end

  desc "Run all target shadow-read gates"
  task all: %i[account_balances budget_periods attention recurrence close_readiness]

  desc "Compare legacy and target Home attention summaries without printing financial values"
  task attention: :environment do
    results = BudgetWorkspace.where.not(target_backfilled_at: nil).find_each.map do |workspace|
      Platform::ShadowReads::WorkspaceAttentionMatrix.call(workspace: workspace).as_json
    end
    puts JSON.pretty_generate(results: results)
    abort "Target attention shadow reads found mismatches" if results.any? { |result| !result.fetch(:matched) }
  end

  desc "Compare legacy generated entries with target recurring occurrence coverage"
  task recurrence: :environment do
    results = BudgetWorkspace.where.not(target_backfilled_at: nil).find_each.map do |workspace|
      Platform::ShadowReads::WorkspaceRecurrenceMatrix.call(workspace: workspace).as_json
    end
    puts JSON.pretty_generate(results: results)
    abort "Target recurrence shadow reads found mismatches" if results.any? { |result| !result.fetch(:matched) }
  end

  desc "Compare legacy and target month-close readiness counts"
  task close_readiness: :environment do
    results = BudgetWorkspace.where.not(target_backfilled_at: nil).find_each.map do |workspace|
      Platform::ShadowReads::WorkspaceCloseReadinessMatrix.call(workspace: workspace).as_json
    end
    puts JSON.pretty_generate(results: results)
    abort "Target close-readiness shadow reads found mismatches" if results.any? { |result| !result.fetch(:matched) }
  end
end
