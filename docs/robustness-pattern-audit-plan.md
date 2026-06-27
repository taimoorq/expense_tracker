# Robustness Pattern Audit Plan

Status: planning.

## Goal

Evaluate the app from the standpoint of what it is for, what it does, and what
needs to stay reliable as the product grows. Use that understanding to choose
design patterns that make the app more robust without forcing a rewrite.

For this app, robustness means:

- user data stays private and correctly scoped
- financial calculations are explainable and reproducible
- recurring month workflows are predictable and idempotent
- account movement can be traced from summary views back to entries
- import and backup flows preserve meaning across versions
- UI state supports the workflow without hiding server-side truth

## Product Frame

Expense Tracker is a private, self-hosted, month-based budgeting app. Its core
value is not live bank sync. Its core value is helping people plan, reuse,
review, and explain a manual budget over time.

The product should optimize for:

- clear month-by-month planning
- reusable recurring transactions
- manual account context and balance snapshots
- auditability of money movement
- backup/restore confidence
- low-friction returning-user workflows

## Discovery Plan

### 1. Map product purpose, personas, and core workflows

Document the app as workflows instead of screens:

- signup and financial rhythm setup
- overview and weekly check-in
- month creation and month cloning
- recurring transaction setup
- recurring generation into a month
- manual and wizard-based entry creation
- CSV import
- account setup and snapshots
- account movement drilldowns
- backup export, preview, and restore
- admin user access management

### 2. Inventory capabilities, data ownership, and financial invariants

Use routes, schema, models, services, specs, and docs to map the main concepts:

- `User`
- `BudgetMonth`
- `ExpenseEntry`
- recurring templates:
  - `PaySchedule`
  - `Subscription`
  - `MonthlyBill`
  - `PaymentPlan`
  - `CreditCard`
- `Account`
- `AccountSnapshot`
- backup/import/export services
- overview, account, recurring, and budgeting presenters/services

Capture invariants that should be explicit in code and tests:

- every budgeting record belongs to one user
- one budget month exists per user/month
- linked accounts and entries must belong to the same user
- account snapshots are unique per account/date
- planned entries are projections, not current-balance mutations
- paid entries affect current movement
- recurring generation should avoid accidental duplicates
- backup versions must be previewable before mutation

### 3. Review architecture boundaries

Inspect how responsibilities are split across:

- Active Record models
- controllers and controller concerns
- domain services
- presenters/read models
- ERB partials
- Stimulus controllers
- jobs
- request, service, model, and system specs

Evaluate whether each boundary supports the product purpose:

- controllers orchestrate rather than calculate
- models enforce durable invariants
- services express domain workflows
- presenters prepare complex view state
- Stimulus manages browser behavior only
- tests lock down money math, permissions, and Hotwire flows

### 4. Rank robustness risks by domain

Prioritize areas where regressions are expensive:

- authorization and user data isolation
- money math and account rollforwards
- recurring generation and matching
- credit card estimation/payment flows
- import, backup, restore, and version compatibility
- account movement summaries and drilldowns
- Turbo/modal state for entry and template editing

### 5. Select design patterns that fit the app

Candidate patterns to evaluate:

- DDD-lite bounded contexts for `Budgeting`, `Recurring`, `Accounts`,
  `Overview`, and `Platform`
- command/result service objects for user-triggered workflows
- query objects/read models for dashboards and drilldowns
- value objects for month periods, money amounts, and movement classifications
- policy/scoped access helpers for user-owned records
- idempotent generators for recurring month creation
- versioned schemas/adapters for backup and import data
- presenters/view models for dense Rails views
- characterization tests before high-risk refactors

### 6. Turn findings into a refactor roadmap

Produce a prioritized plan of small, verifiable slices:

- clarify the highest-risk service interfaces
- remove duplicate legacy service entry points where safe
- add missing validations or guard clauses around invariants
- strengthen tests around money math and user scoping
- stabilize Turbo and modal response contracts
- update docs/help text when terminology changes

## Reusable Agent Or MCP Concept

This workflow is reusable beyond this app. The general capability is:

> Given an application repository, infer its product purpose, map its
> functionality, identify robustness-critical invariants, and recommend design
> patterns that fit the existing architecture.

Working name: **Application Robustness Auditor**.

### Best first shape

Start as an agent or skill-style workflow before building a full MCP server.

An agent is best for the first version because most of the value is judgment:

- reading local files
- building a product/domain map
- asking what the app is trying to protect
- comparing current boundaries to intended use
- turning findings into a roadmap

An MCP server becomes useful when we want the workflow available in many AI
clients with structured reusable prompts, resources, and tools.

### MCP fit

MCP servers can expose three useful primitives:

- resources: contextual data such as repo summaries, schema maps, route maps,
  dependency inventories, and previous audit documents
- prompts: reusable workflows such as "map this app's purpose" or "recommend
  robustness patterns"
- tools: callable scanners or generators, such as route extraction, schema
  summarization, test inventory, dependency graph creation, and audit document
  generation

For this purpose, prompts and resources are just as important as tools. The
agent needs structured context and repeatable audit workflows more than it needs
powerful mutation tools.

### Proposed MCP capabilities

Resources:

- `app://summary`
- `app://routes`
- `app://schema`
- `app://models`
- `app://controllers`
- `app://services`
- `app://tests`
- `app://docs`
- `audit://previous-findings`
- `patterns://catalog`

Prompts:

- `map_product_purpose`
- `inventory_capabilities`
- `identify_domain_invariants`
- `audit_architecture_boundaries`
- `rank_robustness_risks`
- `recommend_design_patterns`
- `create_refactor_roadmap`

Tools:

- `scan_repo`
- `summarize_routes`
- `summarize_schema`
- `summarize_tests`
- `detect_framework`
- `find_domain_terms`
- `generate_capability_map`
- `generate_risk_register`
- `write_audit_doc`

Mutation tools should be opt-in and human-approved. The first version should
mostly read, summarize, and write audit documents.

### Output artifacts

The reusable auditor should produce:

- product purpose brief
- capability map
- domain model map
- architecture boundary map
- invariant/risk register
- recommended design patterns
- phased refactor roadmap
- suggested tests for high-risk areas

### Implementation path

1. Create a repo-local agent prompt or skill that runs this workflow manually.
2. Use it on this app and one other app to refine the checklist.
3. Extract stable scanners into a small CLI.
4. Wrap the CLI in an MCP server exposing resources, prompts, and tools.
5. Add optional framework adapters for Rails, Django, Laravel, Express, Next.js,
   and generic static sites.

### Initial safety rules

- read first, write only requested audit artifacts
- never change app code during the audit workflow by default
- avoid running destructive commands
- treat test execution and dependency installation as explicit actions
- keep financial, medical, legal, and authentication domains flagged as
  high-risk by default
- separate observations from recommendations
- make every recommendation traceable to files, workflows, or risks

## Next Step

Use this app as the pilot. Produce the first full audit artifact from the
existing Rails codebase, then turn the repeated parts of that process into the
first version of the reusable agent workflow.
