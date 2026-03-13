# Expense Tracker

A Rails 8 budgeting app for planning and tracking monthly income, bills, subscriptions, debt payments, manual adjustments, and credit-card estimates.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Tech Stack](#tech-stack)
- [Getting Started](#getting-started)
	- [Run Locally](#run-locally)
	- [Run with Docker](#run-with-docker)
- [Authentication](#authentication)
- [How to Use the App](#how-to-use-the-app)
	- [1. Start at the Dashboard](#1-start-at-the-dashboard)
	- [2. Create a Month](#2-create-a-month)
	- [3. Add or Import Entries](#3-add-or-import-entries)
	- [4. Configure Recurring Templates](#4-configure-recurring-templates)
	- [5. Review and Manage a Month](#5-review-and-manage-a-month)
- [Demo and Sample Data](#demo-and-sample-data)
	- [Sample User](#sample-user)
	- [Seeded Demo Month](#seeded-demo-month)
	- [Sample CSV Files](#sample-csv-files)
- [Clone Month Behavior](#clone-month-behavior)
- [Testing and Useful Commands](#testing-and-useful-commands)
- [Troubleshooting](#troubleshooting)
- [Docker Files in this Repo](#docker-files-in-this-repo)

## Overview

Expense Tracker is a personal budgeting app built around monthly planning. Each signed-in user gets private data and can:

- create months from scratch or clone an existing month
- track income and expenses in timeline, calendar, and table views
- import historical CSV data
- generate recurring entries from saved templates
- estimate credit card payments from available leftover cash

## Features

- Private per-user budgeting data with authentication
- Dashboard with month list plus quick CSV import card
- Monthly budget views with Timeline, Calendar, and Entries tabs
- Guided month-creation wizard with fresh and clone flows
- Clone preview showing target month and copied entry count
- Standard add-entry form plus guided entry wizard
- CSV import support with downloadable sample files
- Recurring template support for pay schedules, subscriptions, monthly bills, payment plans, and credit cards
- Complete-month safeguards that hide generation actions on older completed months
- Seeded March 2026 demo data
- Docker support for local development with PostgreSQL

## Tech Stack

- Ruby 4.0.1
- Rails 8.1.2
- PostgreSQL
- Devise
- Turbo + Stimulus
- Tailwind CSS
- RSpec + FactoryBot

## Getting Started

### Run Locally

#### Prerequisites

- Ruby 4.0.1
- Bundler
- PostgreSQL
- libpq development headers
- libvips

Typical macOS setup with Homebrew:

- `brew install postgresql libpq vips`

Make sure PostgreSQL is running before starting the app.

#### Setup

1. Install gems
	 - `bundle install`
2. Prepare the database
	 - `bin/rails db:prepare`
3. Optional: load demo data
	 - `bin/rails db:seed`
4. Start the development server
	 - `bin/dev`

Open http://localhost:3000

### Run with Docker

This repository includes a Docker-based development setup intended to run on any local machine with Docker and Docker Compose.

#### Prerequisites

- Docker Desktop, or Docker Engine + Docker Compose

#### Start the app

1. Build and start the containers
	 - `docker compose up --build`
2. Open the app
	 - http://localhost:3000

Services included:

- `web` — Rails app running via `bin/dev`
- `db` — PostgreSQL 16

The container entrypoint automatically runs `bin/rails db:prepare` when the app starts.

#### Seed demo data in Docker

In another terminal:

- `docker compose exec web bin/rails db:seed`

#### Stop the stack

- `docker compose down`

To also remove the database volume:

- `docker compose down -v`

## Authentication

The app requires sign-in.

You can:

- create a new account from the sign-up page
- sign in with your own account
- use the seeded demo account after running `bin/rails db:seed`

All budget months, entries, imports, and recurring templates are scoped to the signed-in user.

## How to Use the App

### 1. Start at the Dashboard

The dashboard is the main landing page after sign-in.

It shows:

- a list of your existing months on the left
- a quick CSV import card on the right
- shortcuts to open or clone a month

Use the quick import card to drag and drop a CSV file or click to browse for one.

### 2. Create a Month

Click `New Month` to open the month wizard.

The wizard supports two flows:

- `Clone an existing month`
	- choose a source month
	- review the success preview
	- create the next available month automatically
- `Start fresh`
	- go to the next step
	- enter the month date, label, income, and notes manually

Cloning is useful when you want to carry a previous month’s structure forward.

### 3. Add or Import Entries

Once a month exists, open it and use one of these methods:

- `Entries` tab
	- add entries manually with the standard form
- `Add Entry with Wizard`
	- use the guided multi-step entry flow
- CSV import
	- import a file from the dashboard
	- imported rows create or update the correct month automatically

Entry fields include:

- date
- payee
- reason/category
- status
- planned amount
- actual amount
- account
- notes

### 4. Configure Recurring Templates

Use the planning templates area to define recurring items that can generate month entries.

Template types include:

- pay schedules
- subscriptions
- monthly bills
- payment plans
- credit cards

These templates let the app create common entries for a month without entering each one by hand.

### 5. Review and Manage a Month

Each budget month has three main views:

- `Timeline`
	- grouped view of entries with totals by group
	- row-level filters for date, payee, reason, and status
	- pill filters based on the actual reason values in that month
- `Calendar`
	- date-based view of entries
	- pill filters using the same month-specific reason values
- `Entries`
	- form and tabular management view for direct editing

Additional month actions:

- `Clone Month`
	- create a new month from the current one
- generation actions
	- available for active or incomplete months
	- hidden when an older month appears complete
- `Recalculate Card Estimates`
	- recomputes estimated credit-card payments from available leftover cash

## Demo and Sample Data

### Sample User

Running `bin/rails db:seed` creates or updates a demo user you can sign in with:

- Email: `demo@example.com`
- Password: `password123!`

You can override these when seeding with:

- `SEED_USER_EMAIL=your-email@example.com`
- `SEED_USER_PASSWORD=your-password`

### Seeded Demo Month

Running `bin/rails db:seed` imports:

- `db/seeds/march_2026_transactions.csv`

The demo seed also:

- attaches all seeded records to the sample user
- creates starter recurring templates for pay, subscriptions, bills, plans, and cards
- keeps demo cashflow positive for the seeded month
- prints a summary of what was created or refreshed

Income values in that demo seed are inflated by 60% for privacy-friendly sample data.

### Sample CSV Files

Available in `public/samples/` and downloadable from the app:

- `monthly_transactions_template.csv`
- `sample_month_common_payments.csv`

Expected transaction columns:

- `Month`
- `Date`
- `Section`
- `Category`
- `Payee`
- `Planned Amount`
- `Actual Amount`
- `Account`
- `Status`
- `Need or Want`
- `Notes`

## Clone Month Behavior

When cloning a month into a new month:

- all entries are copied
- dates are shifted into the target month
- `actual_amount` is cleared
- `status` is reset to `planned`
- `planned_amount` uses the source `actual_amount` when present, otherwise the source `planned_amount`
- the target month is the next available month that does not already exist for that user

## Testing and Useful Commands

### Local

- Start app: `bin/dev`
- Prepare DB: `bin/rails db:prepare`
- Seed data: `bin/rails db:seed`
- Run tests: `bundle exec rspec`
- Rails console: `bin/rails console`
- Autoload check: `bin/rails zeitwerk:check`

### Docker

- Start app: `docker compose up --build`
- Seed data: `docker compose exec web bin/rails db:seed`
- Run tests: `docker compose exec web bundle exec rspec`
- Rails console: `docker compose exec web bin/rails console`
- Stop app: `docker compose down`

## Troubleshooting

### Port 3000 already in use

Stop the process using it, or change the published port in `docker-compose.yml`.

### Database connection problems

- Local: make sure PostgreSQL is running
- Docker: make sure the `db` container is healthy

### Rebuild Docker after gem changes

- `docker compose up --build`

## Docker Files in this Repo

- `Dockerfile` — production-oriented image
- `Dockerfile.dev` — local development image
- `docker-compose.yml` — local multi-container setup

For local Docker development, use `Dockerfile.dev` and `docker-compose.yml`.
