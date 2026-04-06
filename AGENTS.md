# AGENTS.md

## Project Overview

This repository contains the main Expense Tracker application, a self-hosted monthly budgeting app built with Rails.

The app helps users:

- plan budgets one month at a time
- reuse recurring transactions such as paychecks, bills, subscriptions, payment plans, and credit cards
- import CSV activity and track real spending against planned entries
- manage manual account balances and net worth snapshots
- back up and restore user data with versioned JSON exports

The hosted marketing site and user documentation live in a separate frontend repository at `../financetrackingapp`.

## Stack

- Ruby `4.0.1` via `.ruby-version`
- Rails `8.1.2`
- PostgreSQL
- Devise for authentication
- Hotwire with Turbo + Stimulus
- Importmap, not a Node-based frontend build
- Tailwind CSS via `tailwindcss-rails`
- Propshaft for assets
- Chart.js and Apache ECharts loaded from CDN
- RSpec + FactoryBot present alongside Rails' default test framework

## Important Directories

- `app/models` domain models such as `BudgetMonth`, `ExpenseEntry`, `Account`, and recurring transaction types
- `app/services` business logic for month generation, imports, release handling, backups, sankey charts, and overview data
- `app/controllers` user-facing controllers plus admin and auth flows
- `app/javascript/controllers` Stimulus controllers for interactive UI behavior
- `config/releases.yml` source of truth for in-app release notes and GitHub release publishing
- `spec` RSpec coverage for requests, services, models, seeds, and system flows
- `test` Rails test framework files that are still used by current CI
- `docs` supporting documentation for the app repo

## Local Development

Prefer Docker for a quick start:

- `cp .env.example .env`
- `docker compose up --build`

The default host port is `4287`, mapped to Rails port `3000` inside the container.

Compose services:

- `db` uses PostgreSQL 16
- `web` runs `bin/dev`

`bin/dev` uses `Procfile.dev`, which currently starts:

- `bin/rails server -b 0.0.0.0`
- `bin/rails tailwindcss:watch`

If you are running locally without Docker, make sure the Ruby version matches `.ruby-version`. This repo is not friendly to the system Ruby that ships with macOS.

## Common Commands

- `bin/setup`
- `bin/dev`
- `bin/rails server`
- `bin/rails console`
- `bin/rubocop`
- `bin/brakeman --no-pager`
- `bin/bundler-audit`
- `bin/importmap audit`
- `bin/rails test`
- `bundle exec rspec`
- `bundle exec rspec spec/system`

## Testing Notes

This repository currently uses a mixed testing setup.

Observed test coverage locations:

- `test/` contains Rails default tests and is still used by the main CI test job
- `spec/system` is run in CI with RSpec
- `spec/models`, `spec/requests`, `spec/services`, and `spec/db` contain additional RSpec coverage that exists outside the default `bin/rails test` path

Current GitHub Actions behavior:

- lint runs `bin/rubocop -f github`
- Ruby security scans run `bin/brakeman` and `bin/bundler-audit`
- JS dependency scanning runs `bin/importmap audit`
- main test job runs `bin/rails db:test:prepare test`
- system test job builds Tailwind assets and runs `bundle exec rspec spec/system`

When changing behavior, prefer running the narrowest relevant test first, then the broader suite if the change touches shared flows.

## Architecture Notes

- Recurring transaction types are split across models such as `PaySchedule`, `MonthlyBill`, `Subscription`, `PaymentPlan`, and `CreditCard`
- Month creation and roll-forward behavior is service-driven in `app/services/generate_month_*`
- Account-aware linking logic lives in dedicated services and model concerns
- Overview/dashboard behavior is assembled through `app/services/overview`
- Release notes are backed by `AppRelease` and `ReleaseCatalog`, sourced from `config/releases.yml`
- Cloudflare Turnstile support exists in the auth flow through `turnstile` concerns, controllers, and verification services

## Editing Guidance

- Keep terminology consistent with current product language: use "Recurring Transactions" in user-facing copy unless space is tight
- Treat `config/releases.yml` as user-facing product history; new entries should be newest-first
- When changing product behavior or terminology, check whether the frontend repo at `../financetrackingapp` also needs updates to `index.html`, `docs.html`, or shared messaging
- Favor service objects for non-trivial business rules rather than growing controllers or models
- Respect the existing Hotwire/importmap setup; do not introduce a Node bundler unless explicitly requested

## Release and Docs Coordination

- Pushing changes to `config/releases.yml` on `main` triggers `.github/workflows/publish_release.yml`
- The release workflow publishes a GitHub release using the first entry in `config/releases.yml`
- The public marketing/docs site should stay aligned with app screenshots, feature names, and setup instructions in this repo's `README.md`
