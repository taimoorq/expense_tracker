namespace :git_hooks do
  desc "Configure git to use the repository's tracked hooks"
  task :install do
    hooks_path = Rails.root.join(".githooks")
    pre_commit_path = hooks_path.join("pre-commit")

    File.chmod(0o755, pre_commit_path) if pre_commit_path.exist?
    system("git", "config", "core.hooksPath", hooks_path.to_s, exception: true)

    puts "Git hooks configured to use #{hooks_path}"
  end
end
