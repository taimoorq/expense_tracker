# Account Activity Fixtures

These CSV files are generated or hand-authored synthetic account-activity
fixtures. They keep the CSV shapes needed for parser tests while replacing
source descriptions, account metadata, names, dates, categories, and amounts
with deterministic fake data.

The fixture set includes BOA-style bank activity with account summary preamble
lines, a running-balance column, and a non-transaction opening-balance table row
so imports can exercise real institution CSV structure without retaining source
account details.

It also includes a synthetic Citibank Costco-style export with separate Debit
and Credit columns. No source member name, description, date, or amount is
retained.

The Best Buy Citibank fixture is a synthetic, headerless, tab-delimited export
with the same typed four-column layout as the supported source revision. Its
dates, descriptions, details, and amounts are invented test values.

Regenerate the source-derived fixtures with:

```sh
bundle exec ruby script/sanitize_account_activity_exports.rb
```
