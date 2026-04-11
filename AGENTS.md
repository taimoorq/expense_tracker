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

## Business Context

Expense Tracker is designed for people who budget by month and want one place to plan, review, and maintain that budget over time.

The product is intentionally opinionated around a month-based workflow:

- users build or roll forward a month
- recurring transactions provide the starting structure
- manual and imported entries fill in the month as reality changes
- account context helps budgeting and balances stay connected
- overview, help, and backup flows reduce setup friction for self-hosted users

This is not a bank-sync-first app. Manual planning, recurring reuse, account context, privacy, and self-hosting are the core value proposition.

## Core Features

- Overview dashboard with current-month status, recurring progress, account summaries, and quick actions
- Month-by-month budgeting with support for cloning or generating from recurring templates
- Recurring transaction management for pay schedules, subscriptions, monthly bills, payment plans, and credit cards
- Guided entry wizard for fast manual entry creation with optional recurring-template creation
- Multiple month review surfaces including grouped timeline, full list, calendar, breakdown, and money-flow views
- CSV import flows for bringing historical or current month activity into the app
- Manual accounts and balance snapshots for account coverage and net worth tracking
- Backup and restore flows with preview support and versioned JSON export/import
- In-app help and release notes so product guidance stays visible inside the app

## Target Audience

- People or households who budget manually by month rather than relying on live bank-sync categorization
- Self-hosters who want a private budgeting tool they can run themselves
- Users who value recurring planning structure, account context, and month roll-forward workflows

When making product or UX decisions, optimize for clarity, trust, and reducing budgeting friction for returning users.

## Stack

- Ruby `4.0.1` via `.ruby-version`
- Rails `8.1.2`
- PostgreSQL
- Devise for authentication
- Solid Queue, Solid Cache, and Solid Cable from Rails
- Hotwire with Turbo + Stimulus
- Importmap, not a Node-based frontend bundler
- Tailwind CSS via `tailwindcss-rails`
- Propshaft for assets
- Chart.js and Apache ECharts loaded from CDN
- RSpec + FactoryBot present alongside Rails' default test framework

## Important Directories

- `app/models` domain models such as `BudgetMonth`, `ExpenseEntry`, `Account`, and recurring transaction types
- `app/services` business logic for budgeting, recurring generation, accounts, overview, backups, and platform concerns
- `app/controllers` user-facing controllers plus admin and auth flows
- `app/helpers` view-oriented helper methods shared by ERB templates
- `app/javascript/controllers` Stimulus controllers for interactive UI behavior
- `app/views` ERB views, Turbo frame content, and modal partials
- `app/jobs` background jobs, including recurring-entry completion flows
- `config/releases.yml` source of truth for in-app release notes and GitHub release publishing
- `spec` RSpec coverage for requests, services, models, DB, and system flows
- `test` Rails test framework files that are still used by current CI
- `docs` supporting documentation for the app repo

## Architecture Notes

- The app now leans on domain-oriented services under areas such as `Budgeting`, `Recurring`, `Accounts`, `Overview`, and `Platform`
- `ExpenseEntry` is the main month-instance record; recurring template models describe reusable planning definitions
- Recurring transaction types stay in separate models because their rules differ, but they share common concerns and catalog metadata
- Overview/dashboard behavior is assembled through `app/services/overview` and exposed to the page through a presenter
- Backup/restore logic is service-driven and namespaced under platform services rather than buried in controllers
- Account-aware linking logic lives in dedicated services and model concerns
- Release notes are backed by release services and `config/releases.yml`
- Cloudflare Turnstile support exists in the auth flow through `turnstile` concerns, controllers, and verification services

## Code Style and Structure

- Follow Rails conventions first unless the existing codebase has already established a better local pattern
- Write concise, idiomatic Ruby with descriptive method and variable names
- Prefer double-quoted strings unless single quotes improve readability by avoiding escaping
- Replace repeated conditionals or branching logic with small, named methods or POROs when the behavior starts to sprawl
- Keep controllers focused on authorization, request parsing, orchestration, and response formatting
- Favor service objects or presenters for non-trivial business logic, cross-model workflows, or view-specific composition
- Keep comments focused on why, tradeoffs, or non-obvious side effects rather than narrating straightforward code
- Prefer constants over unexplained magic values when the value has domain meaning
- Respect the app's product language, especially around "Recurring Transactions", months, accounts, and backups

## Hotwire, Turbo, and Stimulus Guidance

- Default to server-rendered HTML and Hotwire flows before reaching for custom JavaScript
- Use Turbo Frames for scoped updates such as modals, editors, side panels, and in-page workflow surfaces
- Use Turbo Streams when multiple parts of a page need to update together after a mutation
- Keep Stimulus controllers focused on UI behavior, state transitions, and browser APIs; do not move business rules out of Rails just because JavaScript is available
- Preserve stable `data-controller`, `data-action`, and `data-*-target` contracts during refactors, especially for modal and wizard flows
- When extracting ERB partials, keep Turbo frame boundaries and Stimulus target ownership explicit so the frontend contract does not become ambiguous
- Prefer progressive enhancement: pages should still make sense when rendered fresh from the server
- Treat modal forms as Turbo-first flows with clear pending, success, and validation-error states
- Reuse shared submit-state behavior where possible so wizard, editor, and template modals stay consistent
- For UI refactors, look for opportunities to move view setup into presenters/helpers while keeping the rendered HTML easy for Turbo to replace

## Frontend and UI Conventions

- Tailwind is the primary styling approach; prefer utility classes over new custom CSS
- Match the existing visual language of the app instead of introducing a new design system page by page
- Keep desktop and mobile layouts both working when adjusting month views, overview cards, or modal flows
- Prefer extracting repeated card, modal, or summary markup into partials once the repeated structure is clear
- Icons should come from the existing icon approach already in the app; do not introduce a second icon system casually
- For charts and dashboards, keep the server-side data contract explicit and make JS initialization resilient to Turbo navigation

## Testing Notes

This repository currently uses a mixed testing setup.

Observed test coverage locations:

- `test/` contains Rails default tests and is still used by the main CI test job
- `spec/system` is run in CI with RSpec
- `spec/models`, `spec/requests`, `spec/services`, and `spec/db` contain additional RSpec coverage that exists outside the default `bin/rails test` path

Current GitHub Actions behavior:

- lint runs `bin/rubocop -f github`
- Ruby security scans run `bin/brakeman --no-pager` and `bin/bundler-audit`
- JS dependency scanning runs `bin/importmap audit`
- main test job runs `bin/rails db:test:prepare test`
- system test job builds Tailwind assets and runs `bundle exec rspec spec/system`

When changing behavior, prefer running the narrowest relevant test first, then broaden out if the change touches shared flows.

## Testing Strategy

- Prefer fast isolated specs for services, models, presenters, and helpers when the logic can be tested without a browser
- Prefer request specs for controller behavior, Turbo responses, authorization, and multi-model mutations
- Use system specs sparingly for high-value Hotwire flows that truly need browser behavior, especially Stimulus or Turbo interaction states
- For Turbo/Stimulus work, a strong pattern is:
  - isolated spec for Ruby-side composition or rendering
  - request spec for Turbo response shape when practical
  - one focused system spec for the end-to-end browser behavior
- Add characterization coverage before large refactors in legacy or controller-heavy code
- Avoid testing private methods directly; extract a PORO or presenter if the logic deserves direct tests
- Use factories thoughtfully; keep them lean and prefer explicit setup over dense callback chains

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

## Editing Guidance

- Always read the surrounding files before changing patterns that may be shared across other month, modal, or recurring flows
- Favor editing existing files and extending established patterns before introducing new abstractions
- Keep month workflow language and product terminology consistent with the README and in-app copy
- Treat `config/releases.yml` as user-facing product history; new entries should be newest-first
- When changing product behavior or terminology, check whether the frontend repo at `../financetrackingapp` also needs updates to `index.html`, `docs.html`, or shared messaging
- Favor service objects, presenters, or concerns for non-trivial business rules rather than growing controllers, helpers, or Active Record models
- Respect the existing Hotwire/importmap setup; do not introduce a Node bundler unless explicitly requested
- When refactoring view code, preserve the Turbo and Stimulus contract unless the task explicitly includes updating the frontend behavior

## Code Review and Refactoring Guidance

- Watch for controller actions that are doing too much orchestration, derivation, or branching; they are usually candidates for services or presenters
- When a view starts accumulating many locals or repeated partial setup, consider a presenter or smaller partial extraction
- Keep the boundary between recurring templates, month entries, and accounts clear; avoid reintroducing type-specific branching where a shared interface already exists
- For Hotwire features, review both the server-rendered HTML contract and the browser interaction contract before calling a refactor complete
- Prefer incremental refactors with regression tests over large rewrites, especially in month-generation, import/export, and dashboard flows

## Release and Docs Coordination

- Pushing changes to `config/releases.yml` on `main` triggers `.github/workflows/publish_release.yml`
- The release workflow publishes a GitHub release using the first entry in `config/releases.yml`
- The public marketing/docs site should stay aligned with app screenshots, feature names, and setup instructions in this repo's `README.md`

