# Account Ledger Roadmap

## Goal

Make account balances explainable from recorded snapshots plus monthly activity,
so users can understand what changed, what is still planned, and how projected
balances are derived.

## Current Shape

- `AccountSnapshot` records trusted manual balance points for an account.
- `ExpenseEntry#source_account_id` records where money comes from or is charged.
- `ExpenseEntry#destination_account_id` records where money goes for transfers
  such as credit card payments.
- `Account#current_balance` starts from the latest snapshot and applies paid
  activity after that snapshot.
- The Overview page shows monthly movement charts for linked credit card
  and bank-account activity.

## Data Safety Rules

- Keep snapshots as user-entered reconciliation points.
- Do not rewrite historical entries unless the destination account can be
  inferred confidently from existing credit card template links.
- Keep legacy free-form account labels as display/import fallbacks.
- Treat paid entries as actual balance activity.
- Treat planned entries as projections only; they should never change current
  balances.

## UI Implementation Principles

- Keep Rails-rendered HTML as the source of truth for account, balance, and
  movement screens.
- Prefer Turbo Frames, Turbo Streams, and same-page Turbo morphing before adding
  custom JavaScript flows.
- Use Turbo view transitions as progressive enhancement for smoother updates;
  account and month screens must still be correct without animation support.
- Give repeated ledger, movement, and account rows stable transition names based
  on durable record identity when animating server-rendered updates.
- Keep Stimulus focused on small optimistic UI details such as toggling ARIA,
  data attributes, or classes. Financial math and persistence rules stay in
  Rails services and models.
- Pair visual progress affordances with drilldowns or entry history so the
  motion and charts never hide the underlying financial records.

## Phased Plan

### Phase 1: Explain balances on account detail pages

- Show the latest snapshot, paid activity since that snapshot, and current
  balance.
- Show remaining planned activity and projected balance.
- Add a monthly balance history table that starts from a snapshot and rolls
  forward paid and planned activity month by month.
- Let users inspect the monthly totals behind the account balance.

Completed in this phase:

- Account detail pages now show latest snapshot, paid activity, planned
  activity, current balance, projected balance, and linked-entry activity.
- `Accounts::DetailPage` and `Accounts::BalanceHistory` keep rollforward math
  outside controllers and views.
- Credit card account pages now add a payoff progress panel with paid down this
  month, added this month, remaining balance, and progress since the latest
  snapshot.

### Phase 2: Make transfers first-class in the entry UI

- Make source and destination account labels easier to understand.
- Present credit card payments as money leaving one account and paying down a
  card account.
- Reuse the same model for future transfer-style activity such as loan payments
  or savings transfers.

Completed in this phase:

- Entry editing and the guided entry wizard now label account links as
  "Money leaves / activity account" and "Money goes to".
- Credit card payment setup now uses "Card being paid down" and "Money leaves
  account" for the two sides of scheduled card payments.
- In-app help explains how to use source and destination account links for
  transfer-style entries.

### Phase 3: Add drilldowns from movement charts

- Let users click monthly card or bank movement totals.
- Filter to the entries behind the selected account, month, and movement type.
- Keep the chart as a summary and the entry list as the trust layer.

Completed in this phase:

- Overview card and bank movement sections now expose review links for each
  non-zero month/account/movement total.
- Account movement drilldown pages show the exact entries behind a selected
  overview total.
- Drilldowns are scoped by month, account, and movement type so totals can be
  audited without changing the month page filter model.

### Phase 4: Strengthen backup and restore linkage

- Preserve explicit destination account links when accounts and months are
  restored in the same backup.
- Keep template-based repair for older credit card payment rows.
- Add restore coverage for mixed old and new backup shapes.

Completed in this phase:

- Restores now clear selected scopes in dependency-safe order, then recreate
  accounts before restoring templates and month entries that link to them.
- Imported entries restore explicit "Money leaves" and "Money goes to" account
  links from backup metadata when those accounts are present.
- Account-only restores temporarily unlink existing templates and entries from
  old account records, then relink them by preserved account names after the
  restored accounts exist.

## Decisions For This Release

- Projected balances include planned entries from the current date forward so
  users can see all known scheduled activity after the latest snapshot.
- Account detail pages show summary cards, credit-card goal progress when
  relevant, a linked-entry activity table, and a separate monthly rollforward
  table rather than one dense combined ledger.
- Transfers remain an account-link pattern on regular entries for this release:
  `source_account_id` is where money leaves or activity happens, and
  `destination_account_id` is where money goes.

## End-To-End Test Path

- Start on Overview with linked bank and credit card activity.
- Review credit card added/paid/planned totals and open the movement drilldown.
- Confirm the drilldown shows the exact entries behind the selected account and
  month total.
- Continue from the drilldown to the credit card account page.
- Confirm the account page shows snapshot-based balances, monthly history, paid
  down this month, added this month, and payoff progress.
- Export and restore accounts/months to verify source and destination account
  links survive backup round trips.

## Completion Notes

- Release 0.6.1 ships the planned account-ledger sweep: account balance
  rollups, credit-card payoff progress, overview movement drilldowns, transfer
  account links, safer backup restores, and guided wizard terminology updates.
- The release keeps existing data intact by adding destination-account metadata
  without removing legacy account labels or rewriting historical entries except
  where older credit card payment links can be repaired confidently.
- End-to-end system coverage now exercises the overview movement path through
  the drilldown and into credit-card payoff progress, and the guided wizard
  review-step flow waits for Turbo-loaded modal content before asserting
  recurring-save behavior.
