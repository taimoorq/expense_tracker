# Domain Architecture Plan

This document captures the current domain shape of the app, the target structure
we want to move toward, and a phased plan for getting there without a rewrite.

## Current Domain Map

### Core budgeting

- `User`
  - owns all budgeting, recurring, and account records
- `BudgetMonth`
  - belongs to `User`
  - has many `ExpenseEntry`
- `ExpenseEntry`
  - belongs to `User`
  - belongs to `BudgetMonth`
  - optionally belongs to `source_account`
  - optionally belongs to `source_template` polymorphically

### Recurring templates

- `PaySchedule`
- `Subscription`
- `MonthlyBill`
- `PaymentPlan`
- `CreditCard`

All of these belong to `User`. Most optionally belong to a linked account, and
they generate or inform `ExpenseEntry` rows in a month.

### Accounts

- `Account`
  - belongs to `User`
  - has many `AccountSnapshot`
- `AccountSnapshot`
  - belongs to `Account`

### Support domains

- `AdminUser`
- `AdminAuditLog`
- `AppRelease`
- `ThemePalette`

## Problems In The Current Structure

- Recurring templates are modeled as separate tables, but the app also treats
  them as one conceptual family through registries and parallel services.
- Month generation logic was duplicated across multiple services.
- `ExpenseEntry` stores account provenance in more than one form:
  `account` string, `source_account_id`, `source_file`, and `source_template`.
- Some support-domain objects live alongside Active Record models even though
  they are not part of the persistence layer.

## Target Structure

The target is clearer domain boundaries, not a risky schema rewrite.

### Budgeting

- `BudgetMonth`
- `ExpenseEntry`
- month totals, completion rules, cashflow logic, and month orchestration

### Recurring

- `PaySchedule`
- `Subscription`
- `MonthlyBill`
- `PaymentPlan`
- `CreditCard`
- shared recurring-template contract for:
  - occurrences in a month
  - generated entry attributes
  - entry matching
  - account resolution

### Accounts

- `Account`
- `AccountSnapshot`
- account balance and relinking services

### Platform

- `User`
- preferences and access control
- releases, themes, backup/restore, admin

## Guiding Principles

- Prefer evolutionary refactors over schema-heavy rewrites.
- Keep public controller and route behavior stable while improving internals.
- Reduce duplication by moving shared recurring behavior behind a common
  interface instead of forcing all templates into one table too early.
- Make foreign-key links the canonical source of truth wherever possible.

## Phased Plan

### Phase 1: Shared recurring interface

Status: started

- Add a common recurring-template contract.
- Use that contract to unify month generation for recurring templates.
- Keep existing service names as wrappers to avoid broad churn.

Completed in this phase:

- `RecurringEntryTemplate` concern
- `GenerateMonthRecurringEntries` service
- existing paycheck, subscription, monthly-bill, and payment-plan generators now
  delegate to the shared service

### Phase 2: Strengthen recurring boundaries

Status: in progress

- Move more template-specific generation and matching rules behind the recurring
  interface.
- Decide whether credit-card estimation should conform to the same interface or
  remain a separate allocator with a compatible output contract.
- Reduce direct dependence on `TemplateTypeRegistry` for runtime behavior where
  model-level APIs are clearer.

Completed in this phase:

- recurring templates now expose a shared entry-account interface
- `ExpenseEntry` and relinking logic now resolve template-backed accounts through
  that shared interface instead of branching by template type
- `CreditCard#matches_entry?` now follows the same method shape as the other
  recurring templates
- recurring templates now share a common month-aware matching API, with stable
  account and amount checks handled through model-level hooks instead of ad hoc
  branching in callers

### Phase 3: Normalize provenance and account links

Status: in progress

- Treat `source_template` as the primary origin link when a recurring template
  exists.
- Treat FK-backed accounts as canonical and keep free-form account strings as
  legacy/display fallback.
- Consolidate relinking and provenance repair logic into clearer domain
  services.

Completed in this phase:

- `ExpenseEntry` now normalizes provenance internally:
  - defaults blank `source_file` values to `manual`
  - treats linked/source accounts as canonical for display labels
  - exposes provenance helpers such as source-definition and
    generated-from-template checks
- entry provenance repair now lives in a shared service used by imports and
  entry relinking flows

### Phase 4: Namespace by domain

Status: in progress

- Organize models and services into clearer domain folders/modules:
  - `Budgeting`
  - `Recurring`
  - `Accounts`
  - `Platform`
- Move non-persistent support objects out of the mental “model” bucket where it
  improves clarity.

Completed in this phase:

- support-domain objects now have canonical `Platform` homes:
  - `Platform::AppRelease`
  - `Platform::ReleaseCatalog`
  - `Platform::ThemePalette`
  - `Platform::UserDataExport`
  - `Platform::UserDataImport`
  - `Platform::UserDataImportPreview`
  - `Platform::UserDataSampleBackup`
  - `Platform::UserDataBackupCodec`
- budgeting analytics services now have canonical `Budgeting` homes:
  - `Budgeting::MonthCashflowSankey`
  - `Budgeting::YearCashflowSankey`
  - `Budgeting::AutoCompleteRecurringEntries`
  - `Budgeting::ExpenseEntryProvenanceRepair`
  - `Budgeting::CsvBudgetImporter`
- recurring services now have canonical `Recurring` homes:
  - `Recurring::GenerateMonthRecurringEntries`
  - `Recurring::GenerateMonthPaychecks`
  - `Recurring::GenerateMonthSubscriptions`
  - `Recurring::GenerateMonthMonthlyBills`
  - `Recurring::GenerateMonthPaymentPlans`
  - `Recurring::EstimateMonthCreditCards`
  - `Recurring::EntryWizardTemplateCreator`
  - `Recurring::PlanningTemplateAccountLinking`
  - `Recurring::TemplateCatalog`
- recurring/planning models now expose their own metadata for source files,
  param keys, wizard sections, and permitted attributes through
  `PlanningTemplateMetadata`
- account relinking now has a canonical `Accounts` home:
  - `Accounts::ExpenseEntryAccountLinking`
- overview/dashboard assembly is now split into smaller overview services:
  - `Overview::MonthContext`
  - `Overview::ReviewSummary`
  - `Overview::TemplateSummary`
  - `Overview::CashflowSummary`
  - `Overview::Presenter`
  - `Overview::Presenter` now also owns onboarding step state, next-step card
    actions, and several display-oriented summary strings that were previously
    calculated inline in the ERB template
- top-level compatibility constants remain in place so existing references and
  tests continue to work while the app shifts toward namespaced usage

### Phase 5: Reassess schema consolidation

- After the shared recurring API is mature, revisit whether the five recurring
  tables should remain separate.
- Do not unify tables unless the runtime and validation model become simpler,
  not just more abstract.

## Next Recommended Refactors

1. Continue trimming product-specific orchestration out of controllers now that
   the core domain service boundaries are stable.
2. Keep an eye on whether recurring model metadata should be split further if
   the planning and wizard concerns diverge over time.
3. Consider whether the overview page should eventually move repeated card
   markup into smaller view components now that the presenter owns more of the
   page contract.
