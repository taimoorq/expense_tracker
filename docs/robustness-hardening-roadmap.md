# Robustness Hardening Roadmap

Date: 2026-06-29

## Product Purpose

Expense Tracker is a self-hosted, month-first budgeting app for manual planning, recurring transactions, account context, CSV import, and versioned backup/restore. The highest-value robustness goal is financial trust: users need month totals, recurring generation, account movement, and restores to be explainable, reversible enough, and scoped to their own account.

## Critical Invariants

- User-owned budget data must stay scoped to the signed-in user.
- Backup restore and CSV import must not partially mutate data when validation fails.
- Recurring generation must be idempotent and avoid duplicate month entries.
- Automatically changed financial records must remain explainable.
- Money/date rules must be enforced server-side.
- Destructive actions must be previewed, confirmed, and covered by focused tests.

## Phased Roadmap

### 1. Backup Safety

- Move backup preview state to a deliberate cache store instead of an isolated in-memory store.
- Keep preview tokens scoped to the current user and short-lived.
- Add clear pre-restore guidance that users should export a safety backup before replacing selected data.
- Add focused coverage that preview tokens survive through the configured cache store path.

### 2. CSV Hardening

- Add a preview step before CSV import mutates data.
- Return row-level errors and warnings without creating months or entries.
- Make strict import all-or-nothing inside a transaction.
- Add duplicate detection so existing month rows are visible before import.

### 3. Financial Truth

- Make recurring auto-completion auditable or reviewable.
- Distinguish automatic paid status from user-confirmed paid status.
- Show auto-completed entries in cleanup/review counts so users can confirm them.

### 4. Credit Card Estimate Replacement

- Replace broad `delete_all` estimate cleanup with generated-key-aware replacement.
- Preserve user-edited planned estimates where possible.
- Only replace untouched generated estimates.

### 5. Architecture Cleanup

- Document top-level service aliases as compatibility shims.
- Prefer namespaced services for new work.
- Keep domain rules in models/services/presenters, not views or Stimulus controllers.

### 6. Scale Pass Later

- Paginate admin user lists if hosted installs grow.
- Consider query objects for account/history summaries if large imports become common.
- Revisit Ruby-side summing for account and dashboard totals after realistic data-volume tests.

## Suggested Tests

- Backup preview token survives the configured cache store path.
- CSV preview shows row errors without mutating data.
- CSV import is all-or-nothing on invalid rows in strict mode.
- Auto-completed entries are identifiable and reviewable.
- Re-estimating card payments preserves user-edited planned entries or only replaces untouched generated ones.
- Negative/zero amount rules across entries, recurring templates, plans, and snapshots.

## Working Notes

- Start with data recovery and import flows because they have the highest blast radius.
- Keep each change small enough to verify with a focused spec before widening test coverage.
