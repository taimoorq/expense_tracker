# Documentation

This folder is for documentation that is safe to publish with the source-available
repository.

The GitHub README and the hosted documentation in `../financetrackingapp` describe
the product workflows implemented in this repository. Keep their version labels,
feature names, setup commands, screenshots, captions, and recovery guidance aligned
with `config/releases.yml` and the running application.

Keep local planning, progress notes, audit drafts, risk registers, and
implementation roadmaps in `docs/local-plans/`. That folder is ignored by git so
working notes can stay local unless they are intentionally rewritten as public
documentation.

## Connected and manual workflows

The [implementation record](workflow-implementation.md) tracks the September 2026 workflow update. Public task guides live in the companion site under `docs/simplefin/` and `docs/manual-and-imports/`; keep those guides and in-app Help aligned with shipped actions. New signups are ledger-ready, while existing workspaces preserve the explicit upgrade gate. Bank credentials and refresh schedules stay outside portable backups.
