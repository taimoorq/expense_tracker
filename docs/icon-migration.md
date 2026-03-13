# Open-source icon migration guide

This project currently renders icons through the `app_icon()` helper in [app/helpers/application_helper.rb](../app/helpers/application_helper.rb).

## Current behavior

- `app_icon()` first looks for a local SVG partial in:
  - `app/views/shared/icons/heroicons/`
  - `app/views/shared/icons/open/`
  - `app/views/shared/icons/`
- If no local SVG partial exists, it falls back to the legacy built-in icon paths.
- `tabler_icon()` now aliases to `app_icon()` so the existing UI keeps working during migration.

## Why this structure

This allows the icon system to be migrated in phases without breaking the application:

1. Add open-source local SVG partials one icon at a time.
2. Keep existing views unchanged while icons are replaced.
3. Remove the legacy fallback only after all icons have been migrated.

## How to add a replacement icon

Add a partial named after the icon in:

- `app/views/shared/icons/heroicons/_home.svg.erb`
- `app/views/shared/icons/heroicons/_help.svg.erb`
- `app/views/shared/icons/heroicons/_trash.svg.erb`

Example partial structure:

```erb
<svg
  xmlns="http://www.w3.org/2000/svg"
  viewBox="0 0 24 24"
  class="<%= classes %>"
  <%= %(width="#{size}" height="#{size}").html_safe if size.present? %>
  aria-hidden="true"
  focusable="false"
>
  <% if title.present? %>
    <title><%= title %></title>
  <% end %>
  <!-- paste the open-source SVG paths/shapes here -->
</svg>
```

Prefer SVGs that can inherit text color cleanly or can be normalized to a single-color style.

## Recommended icon sources

To avoid licensed icon packs, use an open-source icon set with clear reuse terms. Good options include:

- Heroicons (MIT)
- Lucide (ISC)
- Phosphor Icons (MIT)

Recommended default for this app: Heroicons.

Reason:

- visually distinct from the current Tabler look
- works well in navigation, auth, and dashboard surfaces
- available as simple SVGs that are easy to inline locally

## Recommended migration order

### Phase 1: highest-visibility shell

- `home`
- `template`
- `calendar-plus`
- `help`
- `chevron-left`
- `chevron-right`
- `arrow-left`
- `login`
- `user-plus`
- `user-circle`

These are used most visibly in [app/views/layouts/application.html.erb](../app/views/layouts/application.html.erb) and [app/views/layouts/authentication.html.erb](../app/views/layouts/authentication.html.erb).

### Phase 2: primary budget workflow

- `copy`
- `cash`
- `repeat`
- `chart-bar`
- `timeline`
- `calendar-month`
- `list`
- `plus`
- `upload`
- `device-floppy`

These drive the main budget month and dashboard screens.

### Phase 3: editing and management actions

- `pencil`
- `file-pencil`
- `trash`
- `x`
- `help`

These appear in entries, modals, and template management.

### Phase 4: auth and supporting surfaces

- `mail`
- `lock`
- `shield-lock`
- `sparkles`

These appear mostly on authentication and marketing-style surfaces.

## Current icon inventory

The current codebase uses these icon names:

- `adjustments`
- `arrow-left`
- `arrow-right`
- `calendar-month`
- `calendar-plus`
- `cash`
- `chart-bar`
- `chevron-down`
- `chevron-left`
- `chevron-right`
- `chevron-up`
- `copy`
- `device-floppy`
- `edit`
- `file-pencil`
- `help`
- `home`
- `list`
- `lock`
- `login`
- `mail`
- `pencil`
- `plus`
- `repeat`
- `shield-lock`
- `sparkles`
- `template`
- `timeline`
- `trash`
- `upload`
- `user-circle`
- `user-plus`
- `x`

## Source and usage reminder

Only add icon assets from open-source sets whose license is compatible with the project.

Recommended practice:

- store SVGs locally in the repository
- do not hotlink third-party icon URLs at runtime
- keep one visual style across the app instead of mixing multiple packs