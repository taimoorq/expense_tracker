# Account Activity Fixtures

These CSV files are generated, synthetic account-activity fixtures. They keep the
CSV shapes needed for parser tests while replacing source descriptions, account
metadata, names, dates, categories, and amounts with deterministic fake data.

The fixture set includes BOA-style bank activity with account summary preamble
lines, a running-balance column, and a non-transaction opening-balance table row
so imports can exercise real institution CSV structure without retaining source
account details.

Regenerate them with:

```sh
bundle exec ruby script/sanitize_account_activity_exports.rb
```
