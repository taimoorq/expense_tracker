# Expense Tracker

A Rails 8 budgeting app for planning and tracking monthly income, bills, subscriptions, debt payments, manual adjustments, and credit-card estimates.

## Features

- Monthly budget views with Timeline, Calendar, and Entries tabs
- CSV import support
- Downloadable sample CSV files for import testing
- Standard add-entry form plus guided entry wizard
- Clone an existing month into a new month
- Seeded March 2026 demo data
- Docker support for local development with PostgreSQL

## Tech stack

- Ruby 4.0.1
- Rails 8.1.2
- PostgreSQL
- Turbo + Stimulus
- Tailwind CSS

## Run locally

### Prerequisites

- Ruby 4.0.1
- Bundler
- PostgreSQL
- libpq development headers
- libvips

Typical macOS setup with Homebrew:

- `brew install postgresql libpq vips`

Make sure PostgreSQL is running before starting the app.

### Setup

1. Install gems
	- `bundle install`
2. Prepare the database
	- `bin/rails db:prepare`
3. Optional: load demo data
	- `bin/rails db:seed`
4. Start the development server
	- `bin/dev`

Open http://localhost:3000

## Run with Docker

This repository includes a Docker-based development setup intended to run on any local machine with Docker and Docker Compose.

### Prerequisites

- Docker Desktop, or Docker Engine + Docker Compose

### Start the app

1. Build and start the containers
	- `docker compose up --build`
2. Open the app
	- http://localhost:3000

Services included:

- `web` — Rails app running via `bin/dev`
- `db` — PostgreSQL 16

The container entrypoint automatically runs `bin/rails db:prepare` when the app starts.

### Seed demo data in Docker

In another terminal:

- `docker compose exec web bin/rails db:seed`

### Stop the stack

- `docker compose down`

To also remove the database volume:

- `docker compose down -v`

## Useful commands

### Local

- Start app: `bin/dev`
- Prepare DB: `bin/rails db:prepare`
- Seed data: `bin/rails db:seed`
- Rails console: `bin/rails console`
- Autoload check: `bin/rails zeitwerk:check`

### Docker

- Start app: `docker compose up --build`
- Seed data: `docker compose exec web bin/rails db:seed`
- Rails console: `docker compose exec web bin/rails console`
- Stop app: `docker compose down`

## Demo and sample data

### Seeded demo month

Running `db:seed` imports:

- `db/seeds/march_2026_transactions.csv`

Income values in that demo seed are inflated by 60% for privacy-friendly sample data.

### Sample CSV files for import testing

Available in `public/samples/` and downloadable from the app:

- `monthly_transactions_template.csv`
- `sample_month_common_payments.csv`

## Clone month behavior

When cloning a month into a new month:

- all entries are copied
- dates are shifted into the target month
- `actual_amount` is cleared
- `status` is reset to `planned`
- `planned_amount` uses the source `actual_amount` when present, otherwise the source `planned_amount`

## Troubleshooting

### Port 3000 already in use

Stop the process using it, or change the published port in `docker-compose.yml`.

### Database connection problems

- Local: make sure PostgreSQL is running
- Docker: make sure the `db` container is healthy

### Rebuild Docker after gem changes

- `docker compose up --build`

## Docker files in this repo

- `Dockerfile` — production-oriented image
- `Dockerfile.dev` — local development image
- `docker-compose.yml` — local multi-container setup

For local Docker development, use `Dockerfile.dev` and `docker-compose.yml`.
