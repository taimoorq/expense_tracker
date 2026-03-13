module ApplicationHelper
  ICON_PARTIAL_PREFIXES = [
    "shared/icons/heroicons",
    "shared/icons/open",
    "shared/icons"
  ].freeze

  def auth_page_theme
    case [ controller_name, action_name ]
    when [ "sessions", "new" ]
      {
        badge: "Welcome back",
        title: "Sign in to your workspace",
        description: "Pick up where you left off, review the month, and keep your budgeting private.",
        gradient: "from-indigo-700 via-violet-700 to-sky-600",
        panel_tint: "from-indigo-500/20 via-violet-500/10 to-sky-400/20",
        glow: "bg-indigo-400/30",
        accent: "text-indigo-200",
        chip: "bg-indigo-500/15 text-indigo-100 ring-indigo-300/30",
        button: "from-indigo-600 to-violet-600 hover:from-indigo-500 hover:to-violet-500",
        feature_icon: "login",
        feature_title: "Secure access",
        feature_copy: "Your budgets, templates, and imports stay scoped to your account."
      }
    when [ "registrations", "new" ]
      {
        badge: "New account",
        title: "Create your budget workspace",
        description: "Start with a clean, private dashboard built for monthly planning and recurring expenses.",
        gradient: "from-emerald-700 via-teal-700 to-cyan-600",
        panel_tint: "from-emerald-500/20 via-teal-500/10 to-cyan-400/20",
        glow: "bg-emerald-400/30",
        accent: "text-emerald-200",
        chip: "bg-emerald-500/15 text-emerald-100 ring-emerald-300/30",
        button: "from-emerald-600 to-teal-600 hover:from-emerald-500 hover:to-teal-500",
        feature_icon: "user-plus",
        feature_title: "Fast onboarding",
        feature_copy: "Get a focused workspace for months, templates, imports, and forecasts in minutes."
      }
    when [ "passwords", "new" ]
      {
        badge: "Password recovery",
        title: "Reset your password",
        description: "We’ll help you get back into your budgeting workspace with a secure reset link.",
        gradient: "from-amber-600 via-orange-600 to-rose-600",
        panel_tint: "from-amber-500/20 via-orange-500/10 to-rose-400/20",
        glow: "bg-amber-400/30",
        accent: "text-amber-100",
        chip: "bg-amber-500/15 text-amber-50 ring-amber-200/30",
        button: "from-amber-500 to-orange-500 hover:from-amber-400 hover:to-orange-400",
        feature_icon: "lock",
        feature_title: "Recovery made simple",
        feature_copy: "Request a reset securely and keep your account protected while you regain access."
      }
    when [ "passwords", "edit" ]
      {
        badge: "Choose a new password",
        title: "Set a fresh password",
        description: "Create a strong password so you can get back to tracking months, imports, and recurring plans.",
        gradient: "from-fuchsia-700 via-violet-700 to-indigo-700",
        panel_tint: "from-fuchsia-500/20 via-violet-500/10 to-indigo-400/20",
        glow: "bg-fuchsia-400/30",
        accent: "text-fuchsia-100",
        chip: "bg-fuchsia-500/15 text-fuchsia-50 ring-fuchsia-200/30",
        button: "from-fuchsia-600 to-violet-600 hover:from-fuchsia-500 hover:to-violet-500",
        feature_icon: "shield-lock",
        feature_title: "Secure reset",
        feature_copy: "Update your credentials without exposing any budgeting data outside your account."
      }
    when [ "registrations", "edit" ]
      {
        badge: "Account settings",
        title: "Manage your account",
        description: "Update your email, refresh your password, or close your account from one secure place.",
        gradient: "from-sky-700 via-indigo-700 to-slate-800",
        panel_tint: "from-sky-500/20 via-indigo-500/10 to-slate-400/20",
        glow: "bg-sky-400/30",
        accent: "text-sky-100",
        chip: "bg-sky-500/15 text-sky-50 ring-sky-200/30",
        button: "from-sky-600 to-indigo-600 hover:from-sky-500 hover:to-indigo-500",
        feature_icon: "pencil",
        feature_title: "Profile control",
        feature_copy: "Keep your login details current while preserving your private budgeting workspace."
      }
    else
      {
        badge: "Expense Tracker",
        title: "Welcome",
        description: "Personal budgeting with private monthly planning.",
        gradient: "from-slate-800 via-indigo-700 to-sky-600",
        panel_tint: "from-slate-500/20 via-indigo-500/10 to-sky-400/20",
        glow: "bg-indigo-400/30",
        accent: "text-slate-200",
        chip: "bg-white/10 text-white ring-white/20",
        button: "from-indigo-600 to-sky-600 hover:from-indigo-500 hover:to-sky-500",
        feature_icon: "shield-lock",
        feature_title: "Private by default",
        feature_copy: "Your budgeting data stays isolated per user."
      }
    end
  end

  def app_icon(name, classes: "h-4 w-4", size: nil, stroke: 1.5, title: nil)
    partial_path = app_icon_partial_path(name)

    if partial_path
      render partial: partial_path, formats: [ :svg ], locals: {
        classes: classes,
        size: size,
        title: title,
        name: name.to_s
      }
    else
      legacy_tabler_icon(name, classes: classes, size: size, stroke: stroke, title: title)
    end
  end

  alias_method :tabler_icon, :app_icon

  def legacy_tabler_icon(name, classes: "h-4 w-4", size: nil, stroke: 1.5, title: nil)
    canonical_name = app_icon_aliases[name.to_s] || name.to_s
    path_data = app_icon_paths[canonical_name] || app_icon_paths["list-bullet"]
    svg_options = {
      xmlns: "http://www.w3.org/2000/svg",
      viewBox: "0 0 24 24",
      fill: "none",
      stroke: "currentColor",
      "stroke-width": stroke,
      "stroke-linecap": "round",
      "stroke-linejoin": "round",
      class: classes,
      aria: { hidden: true },
      focusable: "false"
    }

    svg_options[:role] = "img" if title.present?

    if size.present?
      svg_options[:width] = size
      svg_options[:height] = size
    end

    tag.svg(**svg_options) do
      parts = []
      parts << tag.title(title) if title.present?
      parts.concat(path_data.map { |attrs| tag.path(**attrs) })
      safe_join(parts)
    end
  end

  private

  def app_icon_partial_path(name)
    candidate_names = [ name.to_s, app_icon_aliases[name.to_s] ].compact.map { |icon_name| icon_name.tr("-", "_") }.uniq

    candidate_names.each do |candidate_name|
      prefix = ICON_PARTIAL_PREFIXES.find do |partial_prefix|
        lookup_context.exists?("#{partial_prefix}/#{candidate_name}", [], true, [], formats: [ :svg ])
      end

      return "#{prefix}/#{candidate_name}" if prefix
    end

    nil
  end

  def app_icon_aliases
    {
      "timeline" => "queue-list",
      "list" => "list-bullet",
      "adjustments" => "adjustments-horizontal",
      "cash" => "banknotes",
      "chart-bar" => "chart-bar",
      "home" => "home",
      "template" => "rectangle-stack",
      "calendar-plus" => "calendar-plus",
      "calendar-month" => "calendar-days",
      "device-floppy" => "archive-box-arrow-down",
      "trash" => "trash",
      "pencil" => "pencil-square",
      "file-pencil" => "pencil-square",
      "edit" => "pencil-square",
      "arrow-left" => "arrow-left",
      "arrow-right" => "arrow-right",
      "repeat" => "arrow-path",
      "chevron-down" => "chevron-down",
      "chevron-up" => "chevron-up",
      "chevron-left" => "chevron-left",
      "chevron-right" => "chevron-right",
      "x" => "x-mark",
      "plus" => "plus",
      "copy" => "document-duplicate",
      "help" => "question-mark-circle",
      "login" => "arrow-right-on-rectangle",
      "logout" => "arrow-left-on-rectangle",
      "user-plus" => "user-plus",
      "mail" => "envelope",
      "lock" => "lock-closed",
      "shield-lock" => "shield-check",
      "sparkles" => "sparkles",
      "user-circle" => "user-circle",
      "upload" => "arrow-up-tray",
      "download" => "arrow-down-tray",
      "save" => "check-circle"
    }
  end

  def app_icon_paths
    {
      "queue-list" => [
        { d: "M3.75 6.75h.008v.008H3.75z" },
        { d: "M7.5 6.75h12.75" },
        { d: "M3.75 12h.008v.008H3.75z" },
        { d: "M7.5 12h12.75" },
        { d: "M3.75 17.25h.008v.008H3.75z" },
        { d: "M7.5 17.25h12.75" }
      ],
      "list-bullet" => [
        { d: "M8.25 6.75h12" },
        { d: "M8.25 12h12" },
        { d: "M8.25 17.25h12" },
        { d: "M4.5 6.75h.008v.008H4.5z" },
        { d: "M4.5 12h.008v.008H4.5z" },
        { d: "M4.5 17.25h.008v.008H4.5z" }
      ],
      "adjustments-horizontal" => [
        { d: "M3.75 6.75h6" },
        { d: "M14.25 6.75h6" },
        { d: "M3.75 12h3" },
        { d: "M11.25 12h9" },
        { d: "M3.75 17.25h9" },
        { d: "M17.25 17.25h3" },
        { d: "M9.75 5.25a1.5 1.5 0 1 1 0 3a1.5 1.5 0 0 1 0 -3Z" },
        { d: "M8.25 10.5a1.5 1.5 0 1 1 0 3a1.5 1.5 0 0 1 0 -3Z" },
        { d: "M15.75 15.75a1.5 1.5 0 1 1 0 3a1.5 1.5 0 0 1 0 -3Z" }
      ],
      "banknotes" => [
        { d: "M2.25 7.5A2.25 2.25 0 0 1 4.5 5.25h15A2.25 2.25 0 0 1 21.75 7.5v9A2.25 2.25 0 0 1 19.5 18.75h-15A2.25 2.25 0 0 1 2.25 16.5v-9Z" },
        { d: "M6.75 9.75h.008v.008H6.75z" },
        { d: "M17.25 14.25h.008v.008h-.008z" },
        { d: "M12 9.75a2.25 2.25 0 1 0 0 4.5a2.25 2.25 0 0 0 0 -4.5Z" },
        { d: "M4.5 12a3.75 3.75 0 0 0 3.75 -3.75" },
        { d: "M15.75 15.75A3.75 3.75 0 0 0 19.5 12" }
      ],
      "chart-bar" => [
        { d: "M3.75 19.5h16.5" },
        { d: "M6.75 16.5V10.5" },
        { d: "M12 16.5V6.75" },
        { d: "M17.25 16.5V12" }
      ],
      "home" => [
        { d: "M2.25 12 9.204 5.046a1.125 1.125 0 0 1 1.592 0L21.75 12" },
        { d: "M4.5 9.75V19.5A2.25 2.25 0 0 0 6.75 21.75h10.5A2.25 2.25 0 0 0 19.5 19.5V9.75" },
        { d: "M9.75 21.75v-6a2.25 2.25 0 0 1 2.25 -2.25h0a2.25 2.25 0 0 1 2.25 2.25v6" }
      ],
      "rectangle-stack" => [
        { d: "M4.5 6.75A2.25 2.25 0 0 1 6.75 4.5h10.5a2.25 2.25 0 0 1 2.25 2.25v4.5a2.25 2.25 0 0 1 -2.25 2.25H6.75A2.25 2.25 0 0 1 4.5 11.25v-4.5Z" },
        { d: "M6.75 13.5h10.5A2.25 2.25 0 0 1 19.5 15.75v1.5a2.25 2.25 0 0 1 -2.25 2.25H6.75A2.25 2.25 0 0 1 4.5 17.25v-1.5A2.25 2.25 0 0 1 6.75 13.5Z" }
      ],
      "calendar-plus" => [
        { d: "M8.25 3.75v2.25" },
        { d: "M15.75 3.75v2.25" },
        { d: "M3.75 8.25h16.5" },
        { d: "M6.75 5.25h10.5A2.25 2.25 0 0 1 19.5 7.5v10.5a2.25 2.25 0 0 1 -2.25 2.25H6.75A2.25 2.25 0 0 1 4.5 18V7.5a2.25 2.25 0 0 1 2.25 -2.25Z" },
        { d: "M12 11.25v5.25" },
        { d: "M9.375 13.875h5.25" }
      ],
      "calendar-days" => [
        { d: "M8.25 3.75v2.25" },
        { d: "M15.75 3.75v2.25" },
        { d: "M3.75 8.25h16.5" },
        { d: "M6.75 5.25h10.5A2.25 2.25 0 0 1 19.5 7.5v10.5a2.25 2.25 0 0 1 -2.25 2.25H6.75A2.25 2.25 0 0 1 4.5 18V7.5a2.25 2.25 0 0 1 2.25 -2.25Z" },
        { d: "M8.25 12h.008v.008H8.25z" },
        { d: "M12 12h.008v.008H12z" },
        { d: "M15.75 12h.008v.008h-.008z" },
        { d: "M8.25 15.75h.008v.008H8.25z" },
        { d: "M12 15.75h.008v.008H12z" },
        { d: "M15.75 15.75h.008v.008h-.008z" }
      ],
      "archive-box-arrow-down" => [
        { d: "M3.75 7.5h16.5" },
        { d: "M4.5 7.5l1.05 11.025A2.25 2.25 0 0 0 7.79 20.25h8.42a2.25 2.25 0 0 0 2.24 -1.725L19.5 7.5" },
        { d: "M9 12.75l3 3m0 0l3 -3m-3 3v-6" }
      ],
      "trash" => [
        { d: "M14.74 9l-.346 9m-4.788 0L9.26 9m9.968 -3.21c.342.052.682.107 1.022.166" },
        { d: "M3.98 5.79c.34-.059.68-.114 1.022 -.165m0 0A48.108 48.108 0 0 1 12 5.25c2.291 0 4.536.16 6.718.46m-13.436 0L6 5.25m0 0A2.25 2.25 0 0 1 8.244 3h7.512A2.25 2.25 0 0 1 18 5.25m-12 0h12" }
      ],
      "pencil-square" => [
        { d: "M16.862 4.487a2.625 2.625 0 1 1 3.712 3.712L7.5 21.273l-4.5 1.125 1.125 -4.5L16.862 4.487Z" },
        { d: "M18.75 12.75V19.5A2.25 2.25 0 0 1 16.5 21.75H4.5A2.25 2.25 0 0 1 2.25 19.5V7.5A2.25 2.25 0 0 1 4.5 5.25h6.75" }
      ],
      "arrow-left" => [
        { d: "M10.5 19.5 3 12m0 0 7.5 -7.5M3 12h18" }
      ],
      "arrow-right" => [
        { d: "M13.5 4.5 21 12m0 0 -7.5 7.5M21 12H3" }
      ],
      "arrow-path" => [
        { d: "M16.023 9.348h4.992V4.356" },
        { d: "M2.985 19.644v-4.992h4.992" },
        { d: "M4.94 9.348A8.25 8.25 0 0 1 18.364 5.636L21.015 8.25" },
        { d: "M19.06 14.652A8.25 8.25 0 0 1 5.636 18.364L2.985 15.75" }
      ],
      "chevron-down" => [
        { d: "m19.5 8.25 -7.5 7.5 -7.5 -7.5" }
      ],
      "chevron-up" => [
        { d: "m4.5 15.75 7.5 -7.5 7.5 7.5" }
      ],
      "chevron-left" => [
        { d: "m15.75 19.5 -7.5 -7.5 7.5 -7.5" }
      ],
      "chevron-right" => [
        { d: "m8.25 4.5 7.5 7.5 -7.5 7.5" }
      ],
      "x-mark" => [
        { d: "M6 18 18 6M6 6l12 12" }
      ],
      "plus" => [
        { d: "M12 4.5v15m7.5 -7.5h-15" }
      ],
      "document-duplicate" => [
        { d: "M15.75 17.25v3.375c0 .621 -.504 1.125 -1.125 1.125H6.375a1.125 1.125 0 0 1 -1.125 -1.125V9.375c0 -.621 .504 -1.125 1.125 -1.125H9.75" },
        { d: "M15 3.75H10.5A2.25 2.25 0 0 0 8.25 6v8.25A2.25 2.25 0 0 0 10.5 16.5H17.25A2.25 2.25 0 0 0 19.5 14.25V8.25L15 3.75Z" },
        { d: "M15 3.75V8.25h4.5" }
      ],
      "question-mark-circle" => [
        { d: "M12 18h.008v.008H12z" },
        { d: "M9.75 9a2.25 2.25 0 1 1 2.818 2.186c-.415.14 -.693.53 -.693.968V12.75" },
        { d: "M21 12a9 9 0 1 1 -18 0a9 9 0 0 1 18 0Z" }
      ],
      "arrow-right-on-rectangle" => [
        { d: "M15.75 9V5.25A2.25 2.25 0 0 0 13.5 3h-7.5a2.25 2.25 0 0 0 -2.25 2.25v13.5A2.25 2.25 0 0 0 6 21h7.5a2.25 2.25 0 0 0 2.25 -2.25V15" },
        { d: "M18 12H9.75" },
        { d: "M15 9l3 3l-3 3" }
      ],
      "arrow-left-on-rectangle" => [
        { d: "M8.25 9V5.25A2.25 2.25 0 0 1 10.5 3H18a2.25 2.25 0 0 1 2.25 2.25v13.5A2.25 2.25 0 0 1 18 21h-7.5a2.25 2.25 0 0 1 -2.25 -2.25V15" },
        { d: "M15 12H6.75" },
        { d: "M9.75 9 6.75 12l3 3" }
      ],
      "user-plus" => [
        { d: "M15 19.128a9.38 9.38 0 0 0 -3 -.478 9.38 9.38 0 0 0 -3 .478" },
        { d: "M12 15.75a4.5 4.5 0 1 0 0 -9a4.5 4.5 0 0 0 0 9Z" },
        { d: "M18.75 8.25v6" },
        { d: "M15.75 11.25h6" },
        { d: "M3 20.25a9 9 0 1 1 18 0" }
      ],
      "envelope" => [
        { d: "M21.75 6.75v10.5A2.25 2.25 0 0 1 19.5 19.5H4.5A2.25 2.25 0 0 1 2.25 17.25V6.75A2.25 2.25 0 0 1 4.5 4.5h15A2.25 2.25 0 0 1 21.75 6.75Z" },
        { d: "m3 7.5 7.928 5.285a1.875 1.875 0 0 0 2.144 0L21 7.5" }
      ],
      "lock-closed" => [
        { d: "M16.5 10.5V7.875a4.5 4.5 0 1 0 -9 0V10.5" },
        { d: "M5.25 10.5h13.5A2.25 2.25 0 0 1 21 12.75v6A2.25 2.25 0 0 1 18.75 21H5.25A2.25 2.25 0 0 1 3 18.75v-6A2.25 2.25 0 0 1 5.25 10.5Z" }
      ],
      "shield-check" => [
        { d: "M9 12.75 11.25 15 15 9.75" },
        { d: "M12 3.75c-2.239 1.498 -4.61 2.25 -7.125 2.25v5.25c0 5.014 3.452 9.22 8.1 10.374a1.125 1.125 0 0 0 .525 0c4.648 -1.154 8.1 -5.36 8.1 -10.374V6c-2.515 0 -4.886 -.752 -7.125 -2.25Z" }
      ],
      "sparkles" => [
        { d: "M9.813 15.904 9 18l-.813 -2.096a4.5 4.5 0 0 0 -2.284 -2.284L3.75 12l2.153 -.813a4.5 4.5 0 0 0 2.284 -2.284L9 6.75l.813 2.153a4.5 4.5 0 0 0 2.284 2.284L14.25 12l-2.153 .813a4.5 4.5 0 0 0 -2.284 2.284Z" },
        { d: "M18.259 8.715 18 9.75l-.259 -1.035a3.375 3.375 0 0 0 -1.956 -1.956L14.75 6.5l1.035 -.259a3.375 3.375 0 0 0 1.956 -1.956L18 3.25l.259 1.035a3.375 3.375 0 0 0 1.956 1.956L21.25 6.5l-1.035 .259a3.375 3.375 0 0 0 -1.956 1.956Z" },
        { d: "M16.5 20.25h.008v.008H16.5z" }
      ],
      "user-circle" => [
        { d: "M17.982 18.725A7.488 7.488 0 0 0 12 15.75a7.488 7.488 0 0 0 -5.982 2.975" },
        { d: "M12 13.5a4.125 4.125 0 1 0 0 -8.25a4.125 4.125 0 0 0 0 8.25Z" },
        { d: "M21 12a9 9 0 1 1 -18 0a9 9 0 0 1 18 0Z" }
      ],
      "check-circle" => [
        { d: "M9 12.75 11.25 15 15 9.75" },
        { d: "M21 12a9 9 0 1 1 -18 0a9 9 0 0 1 18 0Z" }
      ],
      "arrow-down-tray" => [
        { d: "M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5" },
        { d: "M12 3v12" },
        { d: "m8.25 11.25 3.75 3.75 3.75 -3.75" }
      ],
      "arrow-up-tray" => [
        { d: "M3 15.75V18A2.25 2.25 0 0 0 5.25 20.25h13.5A2.25 2.25 0 0 0 21 18v-2.25" },
        { d: "M12 3.75v11.25" },
        { d: "m8.25 7.5 3.75 -3.75 3.75 3.75" }
      ]
    }
  end
end
