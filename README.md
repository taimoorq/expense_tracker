# FinanceTracking.app

FinanceTracking.app 2.0 is a self-hosted Rails app for people who plan their money one month at a time. Build the plan, bring in what actually happened, connect it to your accounts, and keep the reports and source records close enough to verify.

The app favors manual planning and CSV imports over live bank sync. It is a good fit if you want a private, hands-on budget that you control and host yourself.

[Product overview](https://financetracking.app/) · [User guide](https://financetracking.app/docs/) · [Trust center](https://financetracking.app/trust/) · [Support](SUPPORT.md) · [Releases](https://github.com/taimoorq/expense_tracker/releases)

## Contents

- [Quick start](#quick-start)
- [What you can do](#what-you-can-do)
- [Screenshots](#screenshots)
- [How the monthly workflow fits together](#how-the-monthly-workflow-fits-together)
- [Self-hosting](#self-hosting)
- [Demo and sample data](#demo-and-sample-data)
- [Local development](#local-development)
- [Authentication and configuration](#authentication-and-configuration)
- [Security and support](#security-and-support)
- [License](#license)
- [Troubleshooting](#troubleshooting)

## Quick start

Docker is the shortest path to a working local install. It starts the Rails app and PostgreSQL together.

### 1. Start the app

Install Docker Desktop, or Docker Engine with Compose, then run:

```bash
git clone https://github.com/taimoorq/expense_tracker.git
cd expense_tracker
cp .env.example .env
docker compose up --build
```

Open [http://localhost:4287](http://localhost:4287) and create an account at `/users/sign_up`.

If the Overview page loads after sign-in, the app and database are ready.

### 2. Optional: load a complete demo budget

In another terminal, run:

```bash
docker compose exec web env SEED_MODE=users_with_transactions bin/rails db:seed
```

Then sign in with:

- Email: `demo@example.com`
- Password: `password123!`

These credentials are for local evaluation only. Change them before exposing the app to anyone else.

### 3. Stop the app

```bash
docker compose down
```

Your database stays in the Docker volume. `docker compose down -v` also deletes that volume, so use it only when you want to erase the local database.

### Common quick-start options

- Change the host port: set `APP_PORT` in `.env`, or run `APP_PORT=4317 docker compose up --build`.
- Create an admin during startup: set both `ADMIN_USER_EMAIL` and `ADMIN_USER_PASSWORD` in `.env` before starting the containers.
- Sign in as an admin: open `/admin/sign_in` after the admin account has been created.
- Open the app from another device on your LAN: use `http://YOUR_COMPUTER_IP:4287` and allow the port through your firewall.

## What you can do

- Start on Home with the current month, the exact items that need review, plan-versus-actual totals, and links to the records behind each graph.
- Create a month from scratch or copy an earlier month, then reuse paychecks, subscriptions, bills, payment plans, and credit-card payments.
- Add a one-time entry, start from an existing recurring item, or save a new recurring transaction in one focused composer.
- Review imported and manual transactions in Activity, then match or unmatch them from planned items without losing either record.
- Track trusted balances and observations for cash, bank, investment, credit-card, loan, and other accounts.
- Compare live monthly trends, categories, and account movement in Reports, with exact-value tables and source-record drilldowns beside the graphs.
- Close a month to preserve its report evidence, or reopen it before intentionally incorporating late activity.
- Export a complete version 2 JSON backup, optionally encrypt it, preview a restore, and roll back an in-place restore from its encrypted seven-day checkpoint.

The app includes in-product help for day-to-day workflows. The hosted [user guide](https://financetracking.app/docs/) covers the same features in more detail.

## Screenshots

<table>
  <tr>
    <td align="center">
      <img src="app/assets/images/marketing/home-v2.webp" alt="Home showing the current month, exact attention queue, plan and actual totals, and chart-backed financial evidence" width="100%">
      <br>
      <strong>Home</strong>
      <br>
      See what needs attention, understand the month, and open the records behind every total.
    </td>
    <td align="center">
      <img src="app/assets/images/marketing/plan-v2.webp" alt="Plan library showing saved months, plan and actual totals, status, and open or clone actions" width="100%">
      <br>
      <strong>Plan</strong>
      <br>
      Open history, create the next month, or carry an earlier structure forward.
    </td>
  </tr>
  <tr>
    <td align="center">
      <img src="app/assets/images/marketing/month-workspace-v2.webp" alt="Monthly workspace with plan, actual, remaining, and forecast totals plus linked review views" width="100%">
      <br>
      <strong>Monthly workspace</strong>
      <br>
      Move between budget, breakdown, calendar, and planning views without losing the month.
    </td>
    <td align="center">
      <img src="app/assets/images/marketing/activity-v2.webp" alt="Activity workspace listing imported and manual transactions with match state, account, amount, and review controls" width="100%">
      <br>
      <strong>Activity</strong>
      <br>
      Review real transactions and connect them to the plan while preserving both sides.
    </td>
  </tr>
  <tr>
    <td align="center">
      <img src="app/assets/images/marketing/accounts-v2.webp" alt="Accounts overview with trusted balance observations, current and projected balances, and net-worth trend" width="100%">
      <br>
      <strong>Accounts</strong>
      <br>
      Reconcile trusted balances, planned movement, current position, and net worth.
    </td>
    <td align="center">
      <img src="app/assets/images/marketing/reports-v2.webp" alt="Reports showing monthly trend graphs, category totals, source labels, and exact-value drilldowns" width="100%">
      <br>
      <strong>Reports</strong>
      <br>
      Compare trends and categories, then open the exact records behind the result.
    </td>
  </tr>
  <tr>
    <td align="center">
      <img src="app/assets/images/marketing/month-close-v2.webp" alt="Closed-month review showing frozen report totals, preserved source records, and reopen guidance" width="100%">
      <br>
      <strong>Close the month</strong>
      <br>
      Preserve the report evidence only after the plan and activity are ready.
    </td>
    <td align="center">
      <img src="app/assets/images/marketing/backup-restore-v2.webp" alt="Backup and Restore showing version 2 export scope, optional encryption, and restore preview guidance" width="100%">
      <br>
      <strong>Backup and restore</strong>
      <br>
      Preview a complete restore and keep an encrypted rollback checkpoint for replacement restores.
    </td>
  </tr>
</table>

## How the monthly workflow fits together

1. **Set up the workspace.** Add the accounts you want to reconcile and the recurring paychecks, bills, subscriptions, payment plans, and card payments you expect.
2. **Build the plan.** Start fresh, copy an earlier month, or generate planned items from the recurring records you want to use.
3. **Bring in reality.** Add a manual transaction or import account activity, then match it to the plan when the records describe the same event.
4. **Review the evidence.** Use Home, the monthly workspace, Accounts, and Reports to compare the plan, actual activity, remaining plan, forecast, and trusted balances. Graphs include exact-value tables or source drilldowns.
5. **Close and recover.** Close a ready month to preserve its reporting evidence. Export a version 2 backup before important changes; an in-place restore creates an encrypted seven-day rollback checkpoint.

Accounts are tracked manually. A balance snapshot provides a known starting point; paid activity explains the current balance, and planned activity contributes to the projected balance.

## Self-hosting

The quick start is intended for local evaluation and development. For a public deployment, use the production Compose stack behind the included Caddy reverse proxy.

### Public HTTPS deployment

1. Copy the production environment template.

   ```bash
   cp .env.production.example .env.production
   ```

2. In `.env.production`, set:

   - `APP_HOST` and `ALLOWED_HOSTS` to your domain
   - a strong `POSTGRES_PASSWORD`
   - the matching password inside `DATABASE_URL`
   - valid `SECRET_KEY_BASE` and `RAILS_MASTER_KEY` values

3. Point the domain's DNS record at the server.

4. Start the stack.

   ```bash
   docker compose --env-file .env.production -f docker-compose.production.yml up -d --build
   ```

Caddy is the only service exposed on ports `80` and `443`. Rails and PostgreSQL remain on the internal Docker network.

### Use a published image

For a repeatable deployment, set a versioned image in `.env.production`:

```dotenv
EXPENSE_TRACKER_IMAGE=ghcr.io/taimoorq/expense_tracker:v2.0.0
```

Then pull and start it without building locally:

```bash
docker compose --env-file .env.production -f docker-compose.production.yml pull web
docker compose --env-file .env.production -f docker-compose.production.yml up -d --no-build
```

Use a version tag instead of `latest` when you want controlled upgrades.

### Private LAN HTTPS

For a private hostname such as `budget.lan`, use Caddy's internal certificate authority:

```bash
docker compose --env-file .env.production \
  -f docker-compose.production.yml \
  -f docker-compose.lan-https.yml \
  up -d --build
```

Each client device must trust the root certificate generated in the `caddy_data` volume. Copy it from the running container with:

```bash
docker compose --env-file .env.production \
  -f docker-compose.production.yml \
  -f docker-compose.lan-https.yml \
  cp caddy:/data/caddy/pki/authorities/local/root.crt ./caddy-local-root.crt
```

If you replace the `caddy_data` volume, Caddy may create a new root certificate that clients must trust again.

### Update an install

Before updating, back up PostgreSQL and compare your environment file with the current example for new settings.

For the local Docker setup from the quick start:

```bash
git pull
docker compose up -d --build
```

For a production install built from source:

```bash
git pull
docker compose --env-file .env.production -f docker-compose.production.yml up -d --build
```

For a production install using a published image, change `EXPENSE_TRACKER_IMAGE` to the new version, then run:

```bash
docker compose --env-file .env.production -f docker-compose.production.yml pull web
docker compose --env-file .env.production -f docker-compose.production.yml up -d --no-build
```

The container runs `bin/rails db:prepare` during startup, so migrations are applied automatically. Keep the PostgreSQL volume intact, and do not run `db:seed` during a normal update.

The app also checks GitHub Releases and shows an update notice when a newer release is available. The related overrides are documented in [.env.example](.env.example).

### FinanceTracking.app 2.0 data transition

Version 2 applies additive database migrations during normal startup. It keeps the existing records and compatible reads in place; it does not silently switch every workspace to the new financial model. Self-hosted operators can inspect and move one workspace at a time after taking both a PostgreSQL backup and an application export.

Run the read-only checks and resumable backfill inside the web container:

```bash
docker compose --env-file .env.production -f docker-compose.production.yml exec web bin/rails data_quality:legacy
docker compose --env-file .env.production -f docker-compose.production.yml exec web env APPLY=1 bin/rails target_backfill:all
docker compose --env-file .env.production -f docker-compose.production.yml exec web bin/rails target_shadow_reads:all
docker compose --env-file .env.production -f docker-compose.production.yml exec web bin/rails target_release:rehearse
docker compose --env-file .env.production -f docker-compose.production.yml exec web bin/rails target_release:status
```

The rehearsal temporarily enables target reads, runs parity and performance checks, exercises the ordered rollback path, and restores the original flags. It prints redacted counts and timings rather than financial values.

Enable one eligible workspace only after the rehearsal passes. Replace the placeholders with a workspace ID from `target_release:status` and your own deployment or change identifier:

```bash
docker compose --env-file .env.production -f docker-compose.production.yml exec web \
  env CONFIRM_WORKSPACE_ID=WORKSPACE_ID CHANGE_ID=YOUR_CHANGE_ID \
  bin/rails 'target_release:enable[WORKSPACE_ID]'
```

If the new reads need to be withdrawn, use the same explicit confirmation. Rollback disables target reads first and preserves dual writes so the evidence needed for diagnosis is not lost:

```bash
docker compose --env-file .env.production -f docker-compose.production.yml exec web \
  env CONFIRM_WORKSPACE_ID=WORKSPACE_ID CHANGE_ID=YOUR_INCIDENT_ID \
  bin/rails 'target_release:rollback[WORKSPACE_ID]'
```

Do not enable a workspace while `target_release:status` reports an incomplete backfill or unresolved discrepancy. Resolve ambiguous historical data through the application’s explicit review flow rather than assigning an account by guess.

## Demo and sample data

`bin/rails db:seed` creates or refreshes a demo user. By default it adds recurring transactions, linked accounts, and balance snapshots without creating month history.

Add six months of sample history with:

```bash
SEED_MODE=users_with_transactions bin/rails db:seed
```

For Docker, prefix the command with `docker compose exec web env`.

### Seed profiles

Set `SEED_PROFILE` to choose the data shape you need:

| Profile | Useful for |
| --- | --- |
| `demo` | A balanced account with recurring items and optional month history |
| `new_user` | Onboarding and empty-state testing |
| `recurring_heavy` | A large recurring library without month history |
| `month_history_heavy` | Twelve months of budget history |
| `account_heavy` | More account types, snapshots, and linked activity |
| `manual_adjustments` | Skipped items, exceptions, and manual entries |
| `all_test_users` | Every profile in one seed run |

Example:

```bash
SEED_PROFILE=all_test_users SEED_MODE=users_with_transactions bin/rails db:seed
```

You can override the primary demo credentials with `SEED_USER_EMAIL` and `SEED_USER_PASSWORD`.

Sample import files live in [`public/samples/`](public/samples/):

- [`monthly_transactions_template.csv`](public/samples/monthly_transactions_template.csv)
- [`sample_month_common_payments.csv`](public/samples/sample_month_common_payments.csv)

## Local development

Use this path when you want to change the app without Docker.

### Prerequisites

- Ruby 4.0.6
- Bundler
- PostgreSQL
- libpq development headers
- libvips

On macOS with Homebrew:

```bash
brew install postgresql libpq vips
```

Start PostgreSQL, then run:

```bash
cp .env.example .env
bin/setup --skip-server
bin/dev
```

Open [http://localhost:3000](http://localhost:3000).

### Stack

- Rails 8.1.3 and Ruby 4.0.6
- PostgreSQL
- Hotwire with Turbo and Stimulus
- Tailwind CSS through `tailwindcss-rails`
- Propshaft and Importmap
- Chart.js and Apache ECharts
- Rails tests plus RSpec and FactoryBot

### Useful commands

| Task | Command |
| --- | --- |
| Prepare or update the development database | `bin/setup --skip-server` |
| Open a Rails console | `bin/rails console` |
| Run Rails tests | `bin/rails test` |
| Run RSpec | `bundle exec rspec` |
| Run RuboCop | `bin/rubocop` |
| Scan Rails code | `bin/brakeman --no-pager` |
| Audit bundled gems | `bin/bundler-audit` |
| Audit importmap packages | `bin/importmap audit` |
| Check autoloading | `bin/rails zeitwerk:check` |
| Install the tracked pre-commit hook | `bin/rails git_hooks:install` |

The pre-commit hook runs RuboCop against staged Ruby files.

### Releases

`config/releases.yml` is the source for the in-app release feed. Add new releases at the top. When that change lands on `main`, [the release workflow](.github/workflows/publish_release.yml) creates the GitHub release and publishes versioned Docker images.

## Authentication and configuration

Regular and admin accounts use separate sign-in pages:

- Regular users register at `/users/sign_up` and sign in at `/users/sign_in`.
- Admins sign in at `/admin/sign_in`.
- The admin console manages user access and audit history. It does not expose users' budgets, entries, recurring transactions, or account balances.

Set both `ADMIN_USER_EMAIL` and `ADMIN_USER_PASSWORD` to create or update an admin through `bin/setup`, the development Docker entrypoint, or `bin/rails admin:bootstrap`. If only one value is present, bootstrap stops with an error instead of creating a partial account.

The public authentication routes include cache-backed rate limiting. Optional Cloudflare Turnstile protection is enabled when the Rails process receives both `TURNSTILE_SITE_KEY` and `TURNSTILE_SECRET_KEY`.

Common settings are documented in:

- [`.env.example`](.env.example) for local development and Docker
- [`.env.production.example`](.env.production.example) for production

## Security and support

Read [SECURITY.md](SECURITY.md) before reporting a suspected vulnerability, and keep security reports out of public issues. The public [trust center](https://financetracking.app/trust/) documents data storage, external requests, included controls, backups, and operator responsibilities.

For installation help, reproducible bugs, workflow feedback, and support boundaries, read [SUPPORT.md](SUPPORT.md). Never publish credentials, complete environment files, database dumps, bank exports, or real financial screenshots.

## License

FinanceTracking.app is source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE.md). You may use, modify, fork, and redistribute the software for permitted noncommercial purposes under that license.

Commercial use requires separate written permission. See [Commercial Licensing](COMMERCIAL-LICENSING.md) or email [hello@financetracking.app](mailto:hello@financetracking.app) before using the software for a commercial purpose.

Because the license restricts commercial use, FinanceTracking.app should be described as source-available, not open source. The repository, Docker image, and environment-variable identifiers continue to use `expense_tracker` for compatibility.

## Troubleshooting

### Port 4287 is already in use

Set another port in `.env`:

```dotenv
APP_PORT=4317
```

Then restart Docker Compose.

### Docker cannot resolve the database host

If the web logs contain `could not translate host name "db" to address`, confirm that both services are running:

```bash
docker compose ps
docker compose logs db
```

Start the complete stack from the repository directory with `docker compose up --build`. The web container expects PostgreSQL at the Compose hostname `db`; running the app container by itself does not provide that network.

### The app works on localhost but not another device

Check the host machine's firewall, use the machine's LAN IP, and confirm both devices are on the same non-isolated network. The development Compose setup accepts non-localhost hosts, but it cannot change firewall or router rules.

### Docker changes break another local network

The Compose files use `172.28.1.0/24` for development and `172.28.2.0/24` for production. If either range overlaps your LAN or VPN, change the corresponding network subnet in the Compose file.

### Gems changed but the container still uses old dependencies

Rebuild the development image:

```bash
docker compose up --build
```

For product workflows and in-app behavior, continue with the [user guide](https://financetracking.app/docs/). For bugs or setup problems, [open a GitHub issue](https://github.com/taimoorq/expense_tracker/issues).
