# Shared form patterns

## Payee and category choices

The entry composer and editor render `shared/value_picker` with the existing form
builder, attribute, and options from `ExpenseEntries::ValueOptions`. The partial
preserves the field name and any caller-owned Stimulus targets and actions.

Choices come from the signed-in user's saved entries across months, recurring
names, and the month's workspace categories, planning items, and ledger payees.
Blank choices are omitted; surrounding spaces and case differences are combined.

The `value-picker` Stimulus controller enhances a native datalist into an editable
combobox. Typing filters existing choices and suggests names one edit away.
Arrow keys highlight choices, Enter accepts a highlighted choice, Escape closes
the list, and Tab keeps the entered text. Pointer selection keeps focus in the
input. The list uses the app's surface, text, and control-border theme tokens.

Unmatched text is a new value and can be saved without selecting an option.
Similar spellings are never automatically substituted. Create and update reuse
the canonical saved spelling only for an exact match after trimming spaces and
ignoring case. Existing duplicate records are not rewritten.

Without JavaScript, the text field and native datalist remain usable. Server
normalization and validation apply in both paths. Browser coverage lives in
`spec/system/entry_value_picker_spec.rb`; scope and persistence contracts have
service and request coverage.
