# Security Policy

FinanceTracking.app stores budgeting and account information in the PostgreSQL database operated by each self-hoster. Security therefore depends on both the application and the way the installation is deployed, updated, accessed, and backed up.

## Supported versions

Security fixes target the latest published stable release. Older releases and modified forks may not receive fixes. Before reporting a problem, confirm it against the current release when it is safe to do so.

## Report a vulnerability privately

Do not open a public GitHub issue for a suspected vulnerability.

Email [hello@financetracking.app](mailto:hello@financetracking.app) with the subject **Security report: short description**. Include only what is needed to reproduce and assess the issue:

- the affected FinanceTracking.app version and deployment method;
- the affected route, feature, or configuration;
- clear reproduction steps or a minimal proof of concept;
- expected and observed behavior;
- the likely impact and any conditions required to trigger it; and
- a safe way to contact you about follow-up questions.

Never send real financial records, bank exports, session cookies, passwords, private keys, production database dumps, or other people's personal information. Use fabricated examples and redact secrets from logs and screenshots.

The maintainer will make a best-effort attempt to acknowledge a report, reproduce it, coordinate a fix, and communicate when disclosure is appropriate. This project does not promise a response or remediation service-level agreement.

## In scope

- vulnerabilities in the current FinanceTracking.app release;
- authentication, authorization, user-data isolation, backup/restore, import, and administrative boundaries;
- the default Docker and production Compose configurations;
- accidental exposure of secrets or sensitive financial data caused by repository code; and
- dependency or supply-chain issues with a concrete impact on the application.

## Usually outside the project scope

- a self-hoster's operating system, reverse proxy, firewall, DNS, storage, database administration, or backup destination;
- unsupported forks or local modifications;
- third-party outages or vulnerabilities without a demonstrated FinanceTracking.app impact;
- social engineering, physical access, credential stuffing with previously leaked passwords, denial-of-service testing, or destructive testing; and
- reports that require access to another person's installation or data without authorization.

## Operator security baseline

For a durable installation:

1. Use the production Compose path with a pinned release image.
2. Set unique, high-entropy Rails and PostgreSQL secrets.
3. Keep HTTPS enabled and restrict registration and network access to the intended users.
4. Back up PostgreSQL and application storage, and test recovery away from production.
5. Update the host, container runtime, database image, reverse proxy, and FinanceTracking.app release deliberately.
6. Keep optional encrypted application backups and infrastructure backups in access-controlled locations.
7. Review the public [security and privacy boundaries](https://financetracking.app/trust/) before exposing the app.

The application includes authentication throttling, host authorization, a restrictive Content Security Policy, secure-cookie/HTTPS production defaults, optional Cloudflare Turnstile, and CI dependency and static-analysis checks. These controls reduce risk but do not make an installation automatically secure.

