# Service Architecture

Expense Tracker uses Rails MVC with small domain-oriented service namespaces for workflow logic that is larger than a model callback or controller action.

## Primary Namespaces

- `Budgeting` owns month setup, month views, entry workflow support, CSV import, visual budget payloads, and month-level presenters.
- `Recurring` owns recurring transaction catalogs, generation, template matching, account relinking, and credit-card estimate generation.
- `Accounts` owns account creation, account movement semantics, balance history, net worth summaries, and drilldowns.
- `Overview` owns the dashboard read model, next-step guidance, and review summaries.
- `Platform` owns backup/restore, release notes, theme palettes, GitHub update checks, and other app-platform concerns.
- `ExpenseEntries` owns entry create/update flows and template editing from month rows.

## Compatibility Aliases

Several files in `app/services/` define top-level constants such as `CsvBudgetImporter`, `EstimateMonthCreditCards`, and `UserDataExport`.

Those are compatibility shims for older code, specs, and release history. New code should prefer the namespaced class directly, for example:

- Use `Budgeting::CsvBudgetImporter`, not `CsvBudgetImporter`.
- Use `Recurring::EstimateMonthCreditCards`, not `EstimateMonthCreditCards`.
- Use `Platform::UserDataExport`, not `UserDataExport`.

Aliases should stay thin. Do not add behavior to a top-level alias file.

## Boundary Rules

- Controllers should authenticate, scope to the current user, parse params, call services, and choose responses.
- Models should enforce durable invariants such as ownership, account/template consistency, enum validity, and simple domain behavior.
- Services should own multi-record mutations, imports, restores, recurring generation, and account movement rules.
- Presenters should own dense UI composition and labels for server-rendered pages.
- Stimulus controllers should only handle browser behavior and progressive enhancement.

## Deferred Scale Pass

The current app is optimized for personal and household budgeting data. If hosted installs or large imports increase data volume, revisit:

- Admin user pagination instead of loading all users.
- Query objects for account history and dashboard totals.
- SQL-backed aggregation for account movement and cashflow summaries.
- Import preview paging for very large CSV files.
