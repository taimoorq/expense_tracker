# Connected and manual financial workflows

Implemented locally on September 23, 2026 for the working 2.4.0 release candidate. This record describes repository behavior; it does not assert that the app or public site has been deployed.

## Delivered behavior

| Area | Result |
| --- | --- |
| First use | New registrations initialize a verified empty ledger. Home gives equal SimpleFIN and manual/statement choices, saves the chosen approach, supports deferring balances and recurring setup, and hides empty dashboard sections on a brand-new workspace. Existing workspaces keep their migration and onboarding history. |
| Workspace settings | Transaction timezone is available in Settings for every user. Changing the starting approach changes guidance, not financial sources or records. |
| Manual Activity | Record income, spending, or two-account transfers directly, with optional time and notes. Form replay creates one movement. Matching is optional; direct manual corrections retain a reversed record. |
| Statement imports | Activity opens an explicit account chooser before the existing CSV preview and background commit. Plan imports remain a separate workflow. |
| Bank review | Activity contains posted review, pending, ignored, accepted history, source filters, and paginated records. Connection pages use the same acceptance and correction commands. |
| Source overlap | A reviewed bank item can attach to an existing manual or CSV transaction with matching account, direction, amount, and currency. The link adds evidence without another posting. Detaching preserves the original movement. |
| Payments | Reserved payments can clear manually, including balances-only and disconnected accounts. Clearing creates one posted movement and allocation; undo reverses it and restores the reservation. |
| Connections | Setup explains read-only access, subscription ownership, mapping, account choices, balance review, the next permitted refresh, and manual continuation. Refresh scheduling remains opt-in and quota-limited. |
| Home, Accounts, and monthly screens | Shared attention links, source details, recorded totals, and received/payment/transfer wording connect the workflows. Existing account balance and running-balance policies remain authoritative. |
| Recurring and Insights | One canonical posted-evidence adapter feeds suggestions and insights from manual, CSV, and accepted bank records. Compatibility workspaces retain their existing reader. Source links identify supporting transactions. |
| Reports and close | Recorded actuals follow transaction dates; matched amounts follow planning periods. Unallocated actuals include partial remainders. Close preview and submit share reservation, correction, and reconciliation checks. New closes freeze both scopes; old closes retain their original evidence. |
| Recovery and documentation | Backup v2 retains new review, duplicate, onboarding, and close metadata. Connections restore disconnected without credentials or refresh schedules. Both public walkthroughs, shared docs, Help, release notes, and synthetic screenshots are aligned. |

## Financial contracts

- Review bank activity before creating its ledger effect. Pending provider records never count as posted actuals.
- Source attachment is an explicit user decision, not a fuzzy automatic merge. A plan with a directly recorded manual payment directs bank review to the existing transaction.
- Matching and unmatching require both the transaction month and planning month to be open or reopened. Closing and these commands share the workspace lock.
- Valid unplanned spending does not require a fabricated plan item. A provider outage or pending item alone does not permanently prevent close; the preview identifies excluded evidence.
- A bank balance does not prove that a reserved payment cleared. Existing bank inclusion and same-day uncertainty rules remain in force.
- Manual recording never initiates a bank payment. Transfers create equal opposite account postings.
- Existing financial records are not silently migrated at signup or when preferences change.

## Schema and rollout

Apply the additive migrations through `20260923130000`, including onboarding preferences, activity review/provider-resolution metadata, and nullable frozen recorded totals. Restart the web and worker processes with the same application secrets. Run the documented audited upgrade for existing workspaces that have not enabled the ledger; new registrations are ready automatically.

Keep financial readers compatible with accepted bank evidence and the new close version. If an entry point must be disabled during rollout, preserve the additive schema and saved evidence. Do not switch a workspace containing bank history back to legacy readers. Use normal reopen, unmatch, detach, and reversal commands for corrections.

The app retains a 15-minute manual cooldown, 12 attempted data requests per rolling 24 hours, opt-in twice-daily scheduling, bounded overlapping history, and a 48-hour bank-staleness indicator. These are application policies, not a promise of real-time or complete institution data.

## Verification

The complete `bin/ci` passed in the Docker test environment with `DATABASE_URL` explicitly set to `expense_tracker_test`:

- Dependency and test-database setup; RuboCop (726 files, no offenses).
- Gem and importmap audits; Brakeman (zero warnings); Tailwind build.
- Rails tests: one test, six assertions, no failures.
- RSpec application suite: 748 examples, zero failures, including representative multi-account performance checks.
- RSpec system suite: 92 examples, zero failures.
- Test-only seed replant.

An earlier system run had two recurring-review timing failures (mobile transition and browser view-transition timeout). Both passed in isolation and the subsequent complete CI run passed without relaxing their assertions. Final focused checks after simplifying the first screen and widening the report table passed 22 Home/onboarding examples and 19 report/authentication/connection request examples. RuboCop remained clean.

Financial regression coverage includes manual replay, income and transfers, foreign-account rejection, closed-period guards, manual match/unmatch/reversal, bank attachment/detachment, disconnected clearing and undo, partial and cross-month actuals, frozen totals, pending exclusion, and backup restore without connection credentials.

Interactive checks used a separate `expense_tracker_workflow_preview` database with synthetic users, accounts, provider records, and balances. They verified desktop onboarding and connection entry, a 390px manual form, bank attachment with no extra transaction, new bank acceptance, disconnected payment clearing, distinct report totals, and closing a mixed-source month while excluding pending data. No live bank credentials or institution requests were used.

## Documentation and remaining release work

The companion site contains complete [SimpleFIN](https://financetracking.app/docs/simplefin/) and [manual/statement](https://financetracking.app/docs/manual-and-imports/) walkthrough sources. Publish them with the matching application release. Screenshots use only synthetic data. All 21 static HTML pages passed internal link, anchor, ID, heading, image-alternative, and JSON-LD checks; both new pages have matching canonical and sitemap entries. Both new guides were inspected in the browser, including a 390px mobile viewport.

Production deployment, release publication, and a real-institution pilot remain operator-owned release steps. Institution coverage, live credential exchange, and production worker configuration were not verified by these local checks. Additional providers, automatic acceptance, automated matching, bulk review, merchant rules, and expanded payday projections remain follow-on work.
