# Robustness Pattern Audit

Status: initial audit for `expense_tracker`.

## Implementation Status

The top findings from this audit have been implemented in the current working
tree:

- CI now includes a non-system RSpec job for model, request, service, and DB
  specs.
- Account movement semantics now flow through a shared
  `Accounts::EntryImpact` classifier.
- Recurring generation and credit card estimate replacement now lock the budget
  month during generation, and credit card estimate cleanup is scoped to
  replaceable planned estimates.
- Backup import and preview now route through versioned v1 adapter classes
  behind the existing public facades.
- CSV import now returns structured warnings for skipped or normalized rows.
- Entry wizard client validation now receives recurring-template compatibility
  metadata from the server presenter.
- Generated recurring entries now carry a durable `generated_entry_key` with a
  database-level uniqueness guard.
- Wizard recurring-template rejection paths now have request-level coverage for
  unsupported template types, unsupported entry sections, and invalid billing
  month counts.

## Product Purpose

Expense Tracker is a private, self-hosted, month-based budgeting app. Its core
purpose is to help people plan a month, reuse recurring financial structure,
track real activity, connect budget entries to manual account balances, and
preserve their data through backups.

The app is intentionally not bank-sync-first. Its strongest product promise is
manual explainability: users should understand where money was planned to go,
what actually happened, how accounts moved, and how recurring structure carries
forward into future months.

Primary audiences:

- people or households who budget manually by month
- self-hosters who want private financial data management
- users who value recurring planning, account context, and auditability more
  than automated bank categorization

## Core Workflows

- Sign up, choose a lightweight financial rhythm, and land on the Overview.
- Set up accounts and optional starting balance snapshots.
- Create recurring transactions for paychecks, subscriptions, bills, payment
  plans, and credit card payment estimates.
- Create a fresh month or clone an existing month.
- Pull recurring transactions into the month.
- Add or edit one-off entries through the simple form or guided wizard.
- Optionally save wizard-created entries back as recurring transactions.
- Import CSV activity into months.
- Review the month through timeline, calendar, list, breakdown, and chart views.
- Trace account movement from overview charts to drilldown entries.
- Export, preview, and restore versioned backup JSON, optionally encrypted.
- Admin users manage user access state without entering users' financial data.

## Capability Map

### Identity and access

- Devise-backed user and admin authentication.
- User suspension and admin audit logs.
- Public auth rate limiting and Turnstile hooks.
- Separation between admin identity management and user financial dashboards.

### Budgeting

- Month index, current-month overview, month creation, cloning, and review tabs.
- Expense entries with planned, paid, and skipped states.
- Section/category/payee/amount/date/account metadata.
- Auto-completion for due recurring entries.

### Recurring planning

- Pay schedules, subscriptions, monthly bills, payment plans, and credit cards.
- Shared recurring-template metadata and generation interfaces.
- Month generation runner for recurring entry creation and credit card estimate
  creation.
- Entry wizard integration for creating or linking recurring items.

### Accounts and movement

- Manual accounts, active/inactive state, net-worth inclusion, and cash
  inclusion.
- Account snapshots as reconciliation points.
- Current and projected balances derived from snapshots plus paid/planned
  entries.
- Movement summaries and drilldowns for credit cards and bank accounts.

### Backup, restore, and import

- Versioned JSON exports by scope.
- Optional password encryption for backup payloads.
- Preview-before-import workflow with preview tokens.
- Transactional restore of selected data sections.
- CSV import for transaction or month-summary formats.

### UI and documentation

- Rails-rendered HTML with Turbo and Stimulus enhancement.
- Tailwind UI conventions and chart controllers for Chart.js/ECharts.
- In-app help, release notes, and companion static docs site.

## Domain Model Map

### Platform and identity

- `User` owns all budgeting, recurring, account, and preference data.
- `AdminUser` owns admin sessions and audit-log authorship.
- `AdminAuditLog` records admin access-management actions.
- Platform services handle release notes, themes, backup/restore, update checks,
  and sample data.

### Budgeting

- `BudgetMonth` belongs to `User` and owns `ExpenseEntry` rows.
- `ExpenseEntry` belongs to `User` and `BudgetMonth`.
- Entries optionally link to `source_account`, `destination_account`, and
  polymorphic `source_template`.

### Recurring

- `PaySchedule`, `Subscription`, `MonthlyBill`, `PaymentPlan`, and `CreditCard`
  each belong to `User`.
- Recurring models expose shared metadata through `PlanningTemplateMetadata`.
- Most recurring models use `RecurringEntryTemplate`; credit cards remain a
  compatible estimate allocator rather than a normal recurring source.

### Accounts

- `Account` belongs to `User`.
- `AccountSnapshot` belongs to `Account`.
- Account movement is represented through entry `source_account_id` and
  `destination_account_id`, with legacy free-form `account` labels retained as
  fallback/display/import metadata.

## Critical Invariants

- Every financial record must be scoped to exactly one user.
- A user can have only one budget month for a given `month_on`.
- Account names are unique per user.
- Account snapshots are unique per account/date.
- Entry user, budget month user, linked source/destination accounts, and linked
  recurring template owner must match.
- Planned entries are projections; paid entries drive current account movement.
- Skipped entries must not affect movement summaries.
- Generated recurring entries should be idempotent for a template/month/date.
- Credit card estimates are replaceable planned projections, not durable paid
  history.
- Backup import must be previewed before restore and selected sections should
  replace data transactionally.
- Admin users should not be able to browse user financial dashboards.

## Architecture Boundary Assessment

### What is strong

- Controllers are comparatively thin. Important workflows delegate into
  services such as `Budgeting::MonthCreator`,
  `Recurring::MonthGenerationRunner`, `Accounts::DetailPage`, and
  `Platform::UserDataImport`.
- Domain namespaces already match the product shape: `Budgeting`, `Recurring`,
  `Accounts`, `Overview`, and `Platform`.
- Model validations enforce several high-value ownership invariants, especially
  in `ExpenseEntry` and template/account linking concerns.
- Backup and restore are not hidden in controllers. They have codec, preview,
  import, export, sample, and notice services.
- Account screens are read-model oriented. `Accounts::DetailPage`,
  `Accounts::BalanceHistory`, movement summaries, and drilldowns keep heavy
  page composition outside controllers.
- Stimulus is mostly used for browser behavior, wizard progress, chart loading,
  pending states, and summaries. The server remains the persistence authority.
- The test suite is broad: request specs, model specs, service specs, DB specs,
  and system specs cover many high-risk workflows.

### What needs tightening

- CI currently runs Rails `test` and `spec/system`, but not the non-system RSpec
  suites that cover most service, model, request, and database behavior. This
  leaves many robustness checks outside the push/PR gate.
- Account movement semantics are implemented in several places:
  `Account#account_delta_for`, `Accounts::BalanceHistory`,
  `Accounts::MonthlyMovementSummary`, and `Accounts::MovementDrilldown`.
  The duplicated classification language is understandable today, but it is a
  divergence risk.
- Recurring generation checks for existing entries in Ruby before creating
  rows. That keeps normal reruns idempotent but does not provide a database
  guard against duplicate generation under concurrent requests.
- Credit card estimates use a delete-and-recreate strategy based on
  `source_file`. That is probably correct for planned estimates, but the
  projection replacement rule should be explicit and guarded.
- Backup format versioning exists, but import code is still a direct v1 importer
  rather than a versioned adapter pipeline. This is fine at version 1; it will
  get fragile when the second backup shape appears.
- CSV import is permissive and rescues broad errors. That is user-friendly for
  rough files, but row-level diagnostics would make failed imports more
  trustworthy.
- The entry wizard duplicates some server validation rules in Stimulus for a
  better UX. That is acceptable if the server remains canonical and the shared
  contract stays visible.
- Top-level compatibility service constants still exist beside namespaced
  services. This is pragmatic during migration, but the long-term boundary will
  be clearer once callers consistently use canonical namespaces.

## Risk Register

### High: CI does not run most non-system RSpec coverage

Evidence:

- `.github/workflows/ci.yml` runs `bin/rails db:test:prepare test`.
- The system-test job runs only `bundle exec rspec spec/system`.
- The repo has substantial `spec/models`, `spec/requests`, `spec/services`, and
  `spec/db` coverage.

Why it matters:

Many of the highest-value tests for money math, authorization, backup restore,
and recurring generation can pass locally but fail to guard PRs.

Recommended pattern:

Make test execution an explicit CI contract. Add an RSpec job for
`spec/models spec/requests spec/services spec/db`, or run all non-system specs
in one job and keep browser specs separate.

### High: Account movement classification can drift

Evidence:

- `Account#account_delta_for` defines account balance impact.
- `Accounts::BalanceHistory` applies deltas across snapshots and months.
- `Accounts::MonthlyMovementSummary` classifies movement buckets for charts.
- `Accounts::MovementDrilldown` re-expresses movement matching for audit pages.

Why it matters:

Account balances, overview chart totals, and drilldowns must stay explainable
from the same underlying movement semantics. Divergence here would break user
trust even if individual screens looked plausible.

Recommended pattern:

Introduce a small `Accounts::EntryImpact` or `Accounts::MovementClassifier`
value object that answers:

- whether an entry affects an account
- the signed account delta
- the movement type for summary/drilldown purposes
- whether the entry is current activity or projection

Then have balance history, movement summary, and drilldowns use it.

### High: Backup restore is intentionally destructive

Evidence:

- Import preview is required before restore.
- Import clears selected scopes and recreates data inside a transaction.
- Account-only restores unlink references before destroying old accounts.

Why it matters:

This workflow is rare but high consequence. The current structure is careful,
but future backup versions and partial restore combinations will increase the
state space quickly.

Recommended pattern:

Keep the command service, but introduce versioned import adapters:

- `Platform::Backup::V1::Reader`
- `Platform::Backup::V1::Importer`
- future `V2` adapters

The public `UserDataImport` service can remain the stable facade.

### Medium-high: Recurring generation idempotency is app-level only

Evidence:

- `Recurring::GenerateMonthRecurringEntries` skips existing generated entries
  before creating new ones.
- Idempotency depends on matching existing entries rather than a generated-entry
  uniqueness contract.

Why it matters:

Normal reruns are protected, but double-submit or concurrent generation paths
can still create duplicates unless the database has a guard or the command
locks the month/template scope.

Recommended pattern:

Use an idempotent generator command with a durable generated signature. Options:

- partial unique index on generated source/template/month/date where safe
- explicit generated-entry key column
- transaction plus advisory lock around month/template generation

Start with the least invasive option that matches current data.

### Medium-high: Credit card estimate replacement needs a formal rule

Evidence:

- Credit card estimates delete existing estimate entries by source before
  recreating planned estimates.

Why it matters:

Projection replacement is a good UX, but it should never remove paid history or
manual entries accidentally if an estimate row is later edited.

Recommended pattern:

Make "replaceable estimate" an explicit state or predicate. At minimum, scope
deletion to planned credit card estimate rows and wrap replacement in a
transaction. Longer term, treat estimates as generated projections with the
same idempotency model as other recurring entries.

### Medium: CSV import feedback is too coarse for trust-heavy data

Evidence:

- CSV import chooses a parser shape from headers and rescues broad failures.
- Invalid dates or amounts can normalize to `nil` rather than returning a
  structured row error.

Why it matters:

Importing financial data is trust-sensitive. Users need to know whether a file
was faithfully imported or partially normalized.

Recommended pattern:

Use an import result object with row-level errors, warnings, and counts. Keep
the current permissive mode if desired, but surface skipped/normalized fields in
the preview or completion message.

### Medium: Wizard client validation duplicates server rules

Evidence:

- `entry_wizard_controller.js` validates required steps, supported recurring
  template types, and billing-month counts before submit.
- Server models and services also validate persisted records.

Why it matters:

Duplication is acceptable for ergonomics, but can drift when recurring template
rules change.

Recommended pattern:

Keep Stimulus as a fast UX layer, but drive template support, required fields,
and option counts from server-rendered metadata. Add focused request specs for
server rejection and one system spec for the happy-path wizard contract.

## Recommended Patterns

### 1. CI-backed test boundary

Treat the existing spec suite as part of the architecture. Add CI jobs so
service, request, model, and DB specs run on PRs. This is the highest-leverage
robustness improvement because the codebase already has the tests.

### 2. DDD-lite bounded contexts

Continue the current direction rather than replacing it. The useful contexts
are:

- `Budgeting`
- `Recurring`
- `Accounts`
- `Overview`
- `Platform`

Avoid a schema rewrite unless a context boundary is already stable in code and
tests.

### 3. Command/result services

Standardize mutation workflows around explicit command results:

- success/failure
- user-facing message
- counts
- warnings
- affected records
- rollback reason

This fits month creation, entry creation/update, recurring generation, account
creation, import, and backup restore.

### 4. Account movement value object

Create a shared account-impact classifier for financial movement semantics. This
will make balances, charts, and drilldowns all read from the same accounting
language.

### 5. Idempotent generator pattern

Recurring generation should be both user-safe and concurrency-safe. The current
matching API is a good base; add a durable idempotency key or lock once the
generated-entry identity is explicit.

### 6. Versioned backup adapters

Keep `Platform::UserDataExport`, `UserDataImport`, and `UserDataBackupCodec` as
public facades. Move version-specific details behind adapters before adding a
second backup version.

### 7. Read models for dashboards and drilldowns

Continue using query/read-model services for overview, account detail, movement
charts, and drilldowns. Financial dashboard views should stay paired with
auditable detail links.

### 8. Server-rendered UI contracts

Keep Rails-rendered HTML as the source of truth. Stimulus should continue to
manage browser affordances, but server services/models should own calculation,
authorization, and persistence decisions.

## Phased Roadmap

### Phase 1: Put the existing safety net in CI

- Add a CI job for non-system RSpec:
  `bundle exec rspec spec/models spec/requests spec/services spec/db`.
- Keep system specs in their current browser-focused job.
- Optionally add a local `bin/ci` target that mirrors CI rather than only Rails
  default tests.

### Phase 2: Extract account movement semantics

- Add an `Accounts::EntryImpact` or `Accounts::MovementClassifier`.
- Move `Account#account_delta_for` logic behind the shared classifier.
- Rework `BalanceHistory`, `MonthlyMovementSummary`, and `MovementDrilldown` to
  use the shared object.
- Add matrix-style specs for source/destination, income/outflow,
  asset/liability, planned/paid/skipped combinations.

### Phase 3: Harden recurring generation

- Define generated-entry identity explicitly.
- Add a test for repeated generation across every recurring template type.
- Add a concurrency-safe guard through locking or a database uniqueness
  strategy.
- Make credit card estimate replacement explicitly scoped to replaceable
  planned estimates.

### Phase 4: Formalize import/restore adapters

- Introduce backup v1 reader/importer classes behind the current facade.
- Add adapter specs for legacy fields and account/template relinking.
- Keep preview-before-import as a required controller workflow.
- Add row-level CSV import results and warnings.

### Phase 5: Stabilize UI contracts

- Move wizard template compatibility metadata to server-rendered data
  attributes or presenter output.
- Keep client validation as progressive enhancement only.
- Add request specs for invalid wizard/template payloads and keep one focused
  system spec for the browser flow.

### Phase 6: Retire compatibility wrappers gradually

- Track top-level service constants that delegate to namespaced services.
- Move callers to canonical namespaces as nearby files change.
- Delete wrappers only after tests and references no longer depend on them.

## Suggested Tests

- CI: non-system RSpec job covering model, request, service, and DB specs.
- Account movement: matrix specs for account delta and movement classification.
- Recurring generation: idempotency specs for every recurring template type.
- Credit card estimates: tests proving paid/manual history is not deleted by
  estimate regeneration.
- Backup restore: adapter specs for v1 payloads, legacy fields, partial scope
  restores, encrypted payloads, and account/template relinking.
- CSV import: row-level invalid amount/date/header specs.
- Wizard flow: request specs for invalid recurring-template payloads plus one
  system spec for Turbo modal success/failure.

## Highest-Value Next Change

Add the missing non-system RSpec CI job first. It is small, low-risk, and would
immediately make the existing robustness work matter on every PR. After that,
extract shared account movement semantics; that is the highest product-trust
refactor because it ties balances, charts, and drilldowns to one auditable rule.
