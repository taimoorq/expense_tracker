namespace :target_backfill do
  desc "Preview users requiring a target workspace"
  task preview: :environment do
    puts JSON.pretty_generate(
      version: Platform::TargetBackfill::WorkspaceBootstrap::VERSION,
      users: User.count,
      users_without_workspace: User.where.missing(:legacy_owned_budget_workspace).count
    )
  end

  desc "Create target workspaces and populate nullable workspace bridge columns"
  task bootstrap_workspaces: :environment do
    abort("Set APPLY=1 to bootstrap target workspaces.") unless ENV["APPLY"] == "1"

    results = []
    User.find_each do |user|
      results << Platform::TargetBackfill::WorkspaceBootstrap.call(user: user).as_json
    end
    puts JSON.pretty_generate(version: Platform::TargetBackfill::WorkspaceBootstrap::VERSION, results: results)
  end

  desc "Run the complete resumable target-model backfill and parity verification"
  task all: :environment do
    abort("Set APPLY=1 to run the target-model backfill.") unless ENV["APPLY"] == "1"

    users = ENV["USER_ID"].present? ? User.where(id: ENV["USER_ID"]) : User.all
    results = users.find_each.map { |user| Platform::TargetBackfill::Runner.call(user: user).as_json }
    puts JSON.pretty_generate(version: Platform::TargetBackfill::WorkspaceBootstrap::VERSION, results: results)
    abort("One or more workspaces failed target parity.") if results.any? { |result| !result[:success] }
  end
end
