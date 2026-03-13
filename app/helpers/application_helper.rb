module ApplicationHelper
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
			]
		}
	end
end
