module ApplicationHelper
	def auth_page_theme
		case [controller_name, action_name]
		when ["sessions", "new"]
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
		when ["registrations", "new"]
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
		when ["passwords", "new"]
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
		when ["passwords", "edit"]
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
		when ["registrations", "edit"]
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

	def tabler_icon(name, classes: "h-4 w-4", size: nil, stroke: 2)
		path_data = tabler_icon_paths[name.to_s] || tabler_icon_paths["list"]
		svg_options = {
			xmlns: "http://www.w3.org/2000/svg",
			viewBox: "0 0 24 24",
			fill: "none",
			stroke: "currentColor",
			:"stroke-width" => stroke,
			:"stroke-linecap" => "round",
			:"stroke-linejoin" => "round",
			class: classes,
			aria: { hidden: true },
			focusable: "false"
		}

		if size.present?
			svg_options[:width] = size
			svg_options[:height] = size
		end

		tag.svg(**svg_options) do
			safe_join(path_data.map { |attrs| tag.path(**attrs) })
		end
	end

	private

	def tabler_icon_paths
		{
			"timeline" => [
				{ d: "M4 6l2 0" },
				{ d: "M12 6l8 0" },
				{ d: "M4 12l2 0" },
				{ d: "M12 12l8 0" },
				{ d: "M4 18l2 0" },
				{ d: "M12 18l8 0" },
				{ d: "M8 6l0 .01" },
				{ d: "M8 12l0 .01" },
				{ d: "M8 18l0 .01" }
			],
			"list" => [
				{ d: "M9 6l11 0" },
				{ d: "M9 12l11 0" },
				{ d: "M9 18l11 0" },
				{ d: "M5 6l0 .01" },
				{ d: "M5 12l0 .01" },
				{ d: "M5 18l0 .01" }
			],
			"adjustments" => [
				{ d: "M4 6l16 0" },
				{ d: "M7 12l13 0" },
				{ d: "M10 18l10 0" },
				{ d: "M5 6l0 .01" },
				{ d: "M4 12l0 .01" },
				{ d: "M7 18l0 .01" }
			],
			"cash" => [
				{ d: "M7 9m0 1a1 1 0 0 1 1 -1h8a1 1 0 0 1 1 1v4a1 1 0 0 1 -1 1h-8a1 1 0 0 1 -1 -1z" },
				{ d: "M10 13l4 0" },
				{ d: "M12 3v3" },
				{ d: "M6 6h12" },
				{ d: "M4 20h16" }
			],
			"chart-bar" => [
				{ d: "M3 12m0 1a1 1 0 0 1 1 -1h3a1 1 0 0 1 1 1v7a1 1 0 0 1 -1 1h-3a1 1 0 0 1 -1 -1z" },
				{ d: "M10 8m0 1a1 1 0 0 1 1 -1h3a1 1 0 0 1 1 1v11a1 1 0 0 1 -1 1h-3a1 1 0 0 1 -1 -1z" },
				{ d: "M17 4m0 1a1 1 0 0 1 1 -1h3a1 1 0 0 1 1 1v15a1 1 0 0 1 -1 1h-3a1 1 0 0 1 -1 -1z" }
			],
			"home" => [
				{ d: "M5 12l-2 0l9 -9l9 9l-2 0" },
				{ d: "M5 12v7a2 2 0 0 0 2 2h3m4 0h3a2 2 0 0 0 2 -2v-7" },
				{ d: "M9 21v-6a2 2 0 0 1 2 -2h2a2 2 0 0 1 2 2v6" }
			],
			"template" => [
				{ d: "M4 4m0 2a2 2 0 0 1 2 -2h12a2 2 0 0 1 2 2v12a2 2 0 0 1 -2 2h-12a2 2 0 0 1 -2 -2z" },
				{ d: "M7 7h10" },
				{ d: "M7 12h10" },
				{ d: "M7 17h6" }
			],
			"calendar-plus" => [
				{ d: "M16 2v4" },
				{ d: "M8 2v4" },
				{ d: "M4 10h16" },
				{ d: "M11 14h6" },
				{ d: "M14 11v6" },
				{ d: "M4 6m0 2a2 2 0 0 1 2 -2h12a2 2 0 0 1 2 2v10a2 2 0 0 1 -2 2h-4" },
				{ d: "M3 17h3" }
			],
			"calendar-month" => [
				{ d: "M4 7a2 2 0 0 1 2 -2h12a2 2 0 0 1 2 2v11a2 2 0 0 1 -2 2h-12a2 2 0 0 1 -2 -2z" },
				{ d: "M16 3v4" },
				{ d: "M8 3v4" },
				{ d: "M4 11h16" },
				{ d: "M8 15h2v2h-2z" },
				{ d: "M12 15h2v2h-2z" },
				{ d: "M16 15h2v2h-2z" }
			],
			"device-floppy" => [
				{ d: "M6 4m0 2a2 2 0 0 1 2 -2h8l4 4v10a2 2 0 0 1 -2 2h-12a2 2 0 0 1 -2 -2z" },
				{ d: "M10 4l0 4l4 0l0 -4" },
				{ d: "M10 14l4 0" }
			],
			"trash" => [
				{ d: "M4 7l16 0" },
				{ d: "M10 11l0 6" },
				{ d: "M14 11l0 6" },
				{ d: "M5 7l1 12a2 2 0 0 0 2 2h8a2 2 0 0 0 2 -2l1 -12" },
				{ d: "M9 7l0 -3h6l0 3" }
			],
			"pencil" => [
				{ d: "M7 21l3 -1l11 -11a2.828 2.828 0 1 0 -4 -4l-11 11l-1 3" },
				{ d: "M17 5l4 4" }
			],
			"file-pencil" => [
				{ d: "M14 3v4a1 1 0 0 0 1 1h4" },
				{ d: "M17 21h-10a2 2 0 0 1 -2 -2v-14a2 2 0 0 1 2 -2h7l5 5v3" },
				{ d: "M12.5 14.5l4 4" },
				{ d: "M14 17l-1 3l3 -1l5 -5a1.5 1.5 0 0 0 -3 -3z" }
			],
			"edit" => [
				{ d: "M7 21l3 -1l11 -11a2.828 2.828 0 1 0 -4 -4l-11 11l-1 3" },
				{ d: "M17 5l4 4" }
			],
			"arrow-left" => [
				{ d: "M5 12l14 0" },
				{ d: "M5 12l6 6" },
				{ d: "M5 12l6 -6" }
			],
			"repeat" => [
				{ d: "M4 12v-3a3 3 0 0 1 3 -3h13" },
				{ d: "M20 6l-3 -3" },
				{ d: "M20 6l-3 3" },
				{ d: "M20 12v3a3 3 0 0 1 -3 3h-13" },
				{ d: "M4 18l3 3" },
				{ d: "M4 18l3 -3" }
			],
			"chevron-down" => [
				{ d: "M6 9l6 6l6 -6" }
			],
			"chevron-up" => [
				{ d: "M6 15l6 -6l6 6" }
			],
			"chevron-left" => [
				{ d: "M15 6l-6 6l6 6" }
			],
			"chevron-right" => [
				{ d: "M9 6l6 6l-6 6" }
			],
			"x" => [
				{ d: "M18 6l-12 12" },
				{ d: "M6 6l12 12" }
			],
			"plus" => [
				{ d: "M12 5l0 14" },
				{ d: "M5 12l14 0" }
			],
			"copy" => [
				{ d: "M7 7m0 2a2 2 0 0 1 2 -2h8a2 2 0 0 1 2 2v8a2 2 0 0 1 -2 2h-8a2 2 0 0 1 -2 -2z" },
				{ d: "M5 15h-1a2 2 0 0 1 -2 -2v-8a2 2 0 0 1 2 -2h8a2 2 0 0 1 2 2v1" }
			],
			"help" => [
				{ d: "M12 18h.01" },
				{ d: "M12 14a2 2 0 1 0 -2 -2" },
				{ d: "M12 14v-1.5" },
				{ d: "M8 4h8a4 4 0 0 1 4 4v8a4 4 0 0 1 -4 4h-8a4 4 0 0 1 -4 -4v-8a4 4 0 0 1 4 -4" }
			],
			"login" => [
				{ d: "M15 12h-9" },
				{ d: "M12 9l-3 3l3 3" },
				{ d: "M6 4h9a2 2 0 0 1 2 2v2" },
				{ d: "M17 16v2a2 2 0 0 1 -2 2h-9" }
			],
			"user-plus" => [
				{ d: "M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0" },
				{ d: "M16 19a6 6 0 0 0 -12 0" },
				{ d: "M19 8v6" },
				{ d: "M22 11h-6" }
			],
			"mail" => [
				{ d: "M3 7a2 2 0 0 1 2 -2h14a2 2 0 0 1 2 2v10a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2z" },
				{ d: "M3 8l9 6l9 -6" }
			],
			"lock" => [
				{ d: "M8 11v-3a4 4 0 1 1 8 0v3" },
				{ d: "M6 11m0 2a2 2 0 0 1 2 -2h8a2 2 0 0 1 2 2v6a2 2 0 0 1 -2 2h-8a2 2 0 0 1 -2 -2z" },
				{ d: "M12 15l0 2" }
			],
			"shield-lock" => [
				{ d: "M12 3l7 4v5c0 5 -3.5 8.5 -7 10c-3.5 -1.5 -7 -5 -7 -10v-5z" },
				{ d: "M10 11v-1a2 2 0 1 1 4 0v1" },
				{ d: "M9 11h6v4h-6z" }
			],
			"sparkles" => [
				{ d: "M12 3l1.8 4.2l4.2 1.8l-4.2 1.8l-1.8 4.2l-1.8 -4.2l-4.2 -1.8l4.2 -1.8z" },
				{ d: "M5 16l.8 1.7l1.7 .8l-1.7 .8l-.8 1.7l-.8 -1.7l-1.7 -.8l1.7 -.8z" },
				{ d: "M18 15l.8 1.7l1.7 .8l-1.7 .8l-.8 1.7l-.8 -1.7l-1.7 -.8l1.7 -.8z" }
			],
			"user-circle" => [
				{ d: "M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0" },
				{ d: "M6 21a6 6 0 0 1 12 0" },
				{ d: "M12 3a9 9 0 1 1 0 18a9 9 0 0 1 0 -18" }
			]
		}
	end
end
