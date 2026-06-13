# Credit Card Payment Schedule Plan

## Goal

Let a user create a credit card account and optionally schedule the monthly payment for that card in the same flow, without rewriting existing account, planning template, or monthly entry data.

## Existing Shape

Credit card payment planning already uses two account links:

- `credit_cards.linked_account_id` points to the credit card account being paid down.
- `credit_cards.payment_account_id` points to the account that pays the monthly card payment.

Generated monthly rows should continue to use the credit card planning record as their `source_template`, while `expense_entries.source_account_id` points to the paying account. This keeps cashflow tied to the account money leaves from, while preserving the destination card account through the credit card template.

## Data Safety Rules

- Keep all existing columns and fallback strings.
- Do not rewrite historical monthly rows as part of the account creation UI.
- Create new credit card schedules only when the user opts in.
- Preserve existing generated credit card rows with `source_file = "credit_card_estimate"`.
- Backfill or relink only when account names match confidently.
- Keep import/export compatible with older backups that only have the `account` string.

## Implementation Steps

1. Expose both credit card account roles anywhere a generated credit-card row can edit its template.
2. Make backup/import relinking treat `linked_account` and `payment_account` consistently.
3. Add an optional monthly payment schedule section to the new account form when the account type is `credit_card`.
4. Create the account, optional first balance snapshot, and optional credit card schedule in one transaction.
5. Cover the flow with request/service/system tests before changing generation behavior.

## Target Behavior

When a credit card account is created with monthly payment scheduling enabled, the app creates:

- an `Account` with `kind = "credit_card"`;
- an optional `AccountSnapshot`, if opening balance fields are present;
- a `CreditCard` planning record with:
  - `linked_account` set to the new credit card account;
  - `payment_account` set to the selected payment account;
  - `account` set to the payment account name as a legacy fallback;
  - `minimum_payment`, `due_day`, `priority`, `active`, and `notes` from the form.

Existing records continue to work even if one of the account links is blank, because the app still falls back to stored labels such as `account` and `payee`.
