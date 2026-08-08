module TargetReleaseTasks
  module_function

  def workspaces(workspace_id)
    scope = BudgetWorkspace.where.not(target_backfilled_at: nil)
      .where.not(id: MigrationDiscrepancy.status_open.select(:budget_workspace_id))
      .order(:id)
    workspace_id.present? ? scope.where(id: workspace_id) : scope
  end

  def sample_count
    ENV.fetch("SAMPLES", Platform::TargetRelease::PerformanceProbe::DEFAULT_SAMPLES).to_i
  end

  def performance(workspace)
    {
      runtime: Platform::TargetRelease::PerformanceProbe.call(
        workspace: workspace,
        samples: sample_count
      ).as_json,
      query_plans: Platform::TargetRelease::QueryPlanProbe.call(workspace: workspace).as_json
    }
  end

  def passed?(evidence)
    evidence.dig(:runtime, :passed) && evidence.dig(:query_plans, :passed)
  end

  def rehearsal_summary(results)
    runtime_probes = results.flat_map { |result| result.dig(:performance, :runtime, :probes) }
    query_plans = results.flat_map { |result| result.dig(:performance, :query_plans, :plans) }
    {
      workspace_count: results.size,
      passed: results.all? do |result|
        result.dig(:canary, :passed) && passed?(result.fetch(:performance))
      end,
      comparison_count: results.sum { |result| result.dig(:canary, :comparison_count) },
      smoke_read_count: results.sum { |result| result.dig(:canary, :smoke_read_count) },
      every_flag_restored: results.all? { |result| result.dig(:canary, :flags_restored) },
      max_p95_ms_by_probe: runtime_probes.group_by { |probe| probe.fetch(:name) }
        .transform_values { |probes| probes.map { |probe| probe.fetch(:p95_ms) }.max },
      max_select_count_by_probe: runtime_probes.group_by { |probe| probe.fetch(:name) }
        .transform_values { |probes| probes.map { |probe| probe.fetch(:max_select_count) }.max },
      max_query_plan_execution_ms: query_plans.map { |plan| plan.fetch(:execution_time_ms) }.max
    }
  end

  def output_rehearsal(results)
    payload = { summary: rehearsal_summary(results) }
    payload[:results] = results if ENV["VERBOSE"] == "1"
    puts JSON.pretty_generate(payload)
  end

  def confirmed_workspace!(workspace_id)
    abort "Provide one workspace ID." if workspace_id.blank?
    unless ENV["CONFIRM_WORKSPACE_ID"] == workspace_id
      abort "Set CONFIRM_WORKSPACE_ID=#{workspace_id} to confirm this workspace-scoped change."
    end

    BudgetWorkspace.find(workspace_id)
  end

  def change_id!
    ENV["CHANGE_ID"].presence || abort("Set CHANGE_ID to the deployment or incident identifier.")
  end

  def owner_membership(workspace)
    workspace.workspace_memberships.status_active.find_by!(user: workspace.legacy_owner_user)
  end
end

namespace :target_release do
  desc "Measure target read latency, SELECT budgets, and PostgreSQL query plans"
  task :performance, [ :workspace_id ] => :environment do |_task, args|
    results = TargetReleaseTasks.workspaces(args[:workspace_id]).map do |workspace|
      unless workspace.target_reads_enabled?
        abort "Target reads must already be enabled for performance-only evidence (workspace #{workspace.id})"
      end

      TargetReleaseTasks.performance(workspace)
    end
    puts JSON.pretty_generate(results: results)
    abort "Target performance evidence exceeded a release budget" unless results.all? { |result| TargetReleaseTasks.passed?(result) }
  end

  desc "Rehearse target-read enablement, smoke reads, and ordered rollback"
  task :canary, [ :workspace_id ] => :environment do |_task, args|
    run_id = Time.current.utc.strftime("%Y%m%d%H%M%S")
    results = TargetReleaseTasks.workspaces(args[:workspace_id]).map do |workspace|
      Platform::TargetRelease::CanaryRehearsal.call(
        workspace: workspace,
        rehearsal_id: "#{run_id}:#{workspace.id}"
      ).as_json
    end
    puts JSON.pretty_generate(results: results)
    abort "Target-read canary rehearsal failed" unless results.all? { |result| result.fetch(:passed) }
  end

  desc "Run canary rollback first, then measure target reads in a reversible window"
  task :rehearse, [ :workspace_id ] => :environment do |_task, args|
    run_id = Time.current.utc.strftime("%Y%m%d%H%M%S")
    results = TargetReleaseTasks.workspaces(args[:workspace_id]).map do |workspace|
      canary = Platform::TargetRelease::CanaryRehearsal.call(
        workspace: workspace,
        rehearsal_id: "#{run_id}:#{workspace.id}"
      )
      performance = Platform::TargetRelease::ReversibleReadWindow.call(workspace: workspace) do
        TargetReleaseTasks.performance(workspace.reload)
      end
      { canary: canary.as_json, performance: performance }
    end
    abort "No eligible target workspaces were found" if results.empty?
    TargetReleaseTasks.output_rehearsal(results)
    abort "Target release rehearsal failed" unless TargetReleaseTasks.rehearsal_summary(results).fetch(:passed)
  end

  desc "Enable target reads for one explicitly confirmed eligible workspace"
  task :enable, [ :workspace_id ] => :environment do |_task, args|
    workspace = TargetReleaseTasks.confirmed_workspace!(args[:workspace_id])
    result = Platform::TargetRelease::Cutover.call(
      workspace: workspace,
      actor_membership: TargetReleaseTasks.owner_membership(workspace),
      action: "enable",
      change_id: TargetReleaseTasks.change_id!
    )
    puts JSON.pretty_generate(result.as_json)
  end

  desc "Disable target reads first for one explicitly confirmed workspace; preserve target writes"
  task :rollback, [ :workspace_id ] => :environment do |_task, args|
    workspace = TargetReleaseTasks.confirmed_workspace!(args[:workspace_id])
    result = Platform::TargetRelease::Cutover.call(
      workspace: workspace,
      actor_membership: TargetReleaseTasks.owner_membership(workspace),
      action: "rollback",
      change_id: TargetReleaseTasks.change_id!
    )
    puts JSON.pretty_generate(result.as_json)
  end

  desc "Show redacted target-release status for every workspace"
  task status: :environment do
    rows = BudgetWorkspace.order(:id).map do |workspace|
      {
        workspace_id: workspace.id,
        backfill_complete: workspace.target_backfilled_at.present?,
        open_discrepancy_count: workspace.migration_discrepancies.status_open.count,
        target_writes_enabled: workspace.target_writes_enabled?,
        target_reads_enabled: workspace.target_reads_enabled?,
        last_cutover_state: workspace.operation_runs
          .where(operation_type: %w[target_read_enable target_read_rollback])
          .order(created_at: :desc)
          .pick(:state)
      }
    end
    puts JSON.pretty_generate(rows: rows)
  end
end
