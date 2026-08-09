# Run using bin/ci

CI.run do
  step "Setup", "env RAILS_ENV=test bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Importmap vulnerability audit", "bin/importmap audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  step "Assets: Tailwind", "env RAILS_ENV=test bin/rails tailwindcss:build"
  step "Tests: Rails", "env RAILS_ENV=test bin/rails test"
  step "Tests: RSpec", "env RAILS_ENV=test bundle exec rspec spec/models spec/requests spec/services spec/jobs spec/db spec/config"
  step "Tests: System", "env RAILS_ENV=test bundle exec rspec spec/system"
  step "Tests: Seeds", "env RAILS_ENV=test SEED_MODE=users_with_transactions bin/rails db:seed:replant"

  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
