module Platform
  class ThemePalette
    COOKIE_KEY = :expense_tracker_theme

    STATUS_TOKENS = {
      "--ta-info" => "#0369A1",
      "--ta-info-soft" => "#E0F2FE",
      "--ta-success" => "#047857",
      "--ta-success-soft" => "#ECFDF5",
      "--ta-success-contrast" => "#FFFFFF",
      "--ta-warning" => "#92400E",
      "--ta-warning-soft" => "#FFF7ED",
      "--ta-danger" => "#BE123C",
      "--ta-danger-soft" => "#FFF1F2"
    }.freeze

    Theme = Struct.new(:key, :name, :colors, :tokens, keyword_init: true) do
      def css_class
        "ta-theme-#{key}"
      end

      def meta_color
        tokens.fetch(key == "dark" ? "--ta-app-bg" : "--ta-accent")
      end

      def css_variables
        tokens.merge(
          "--ta-color-scheme" => key == "dark" ? "dark" : "light",
          "--ta-shadow-rgb" => rgb_triplet(tokens.fetch("--ta-text")),
          "--ta-accent-rgb" => rgb_triplet(tokens.fetch("--ta-accent")),
          "--ta-canvas" => "var(--ta-app-bg)",
          "--ta-canvas-strong" => "var(--ta-app-bg-strong)",
          "--ta-raised" => "var(--ta-surface)",
          "--ta-inset" => "var(--ta-surface-alt)",
          "--ta-overlay" => "var(--ta-surface)",
          "--ta-text-primary" => "var(--ta-text)",
          "--ta-text-secondary" => "var(--ta-text-muted)",
          "--ta-text-tertiary" => "var(--ta-text-soft)",
          "--ta-focus" => "var(--ta-accent)"
        )
      end

      private

      def rgb_triplet(hex)
        hex.delete("#").scan(/../).map { |component| component.to_i(16) }.join(" ")
      end
    end

    PRESETS = {
      "earth" => {
        name: "Earth",
        colors: %w[#EDE5DF #C3A995 #6F5E53 #8A7968 #3F2D2B],
        tokens: {
          "--ta-app-bg" => "#F5F1ED",
          "--ta-app-bg-strong" => "#ECE4DD",
          "--ta-surface" => "#FFFCFA",
          "--ta-surface-alt" => "#F7F2EE",
          "--ta-surface-subtle" => "#EEE6E0",
          "--ta-text" => "#3F2D2B",
          "--ta-text-muted" => "#66574D",
          "--ta-text-soft" => "#6D5F56",
          "--ta-border" => "#D8CAC0",
          "--ta-border-strong" => "#BAA596",
          "--ta-control-border" => "#8A7466",
          "--ta-accent" => "#6F5E53",
          "--ta-accent-hover" => "#4E3F38",
          "--ta-accent-soft" => "#F1EAE6",
          "--ta-accent-soft-strong" => "#E8DDD5",
          "--ta-accent-muted" => "#BFA995",
          "--ta-accent-contrast" => "#FFFFFF",
          "--ta-feature" => "#76504F",
          "--ta-feature-soft" => "#F4E9E7"
        }
      },
      "indigo" => {
        name: "Smoky Violet",
        colors: %w[#E2DCE7 #B9AFC2 #5E5768 #806E82 #2D2833],
        tokens: {
          "--ta-app-bg" => "#F5F2F7",
          "--ta-app-bg-strong" => "#EAE5EE",
          "--ta-surface" => "#FFFCFF",
          "--ta-surface-alt" => "#F8F5FA",
          "--ta-surface-subtle" => "#EEE9F1",
          "--ta-text" => "#2D2833",
          "--ta-text-muted" => "#5F5666",
          "--ta-text-soft" => "#665C6D",
          "--ta-border" => "#D8D0DE",
          "--ta-border-strong" => "#B9AFC2",
          "--ta-control-border" => "#887D91",
          "--ta-accent" => "#5E5768",
          "--ta-accent-hover" => "#484150",
          "--ta-accent-soft" => "#F0EBF2",
          "--ta-accent-soft-strong" => "#E5DDE9",
          "--ta-accent-muted" => "#B9AFC2",
          "--ta-accent-contrast" => "#FFFFFF",
          "--ta-feature" => "#76516F",
          "--ta-feature-soft" => "#F3EAF1"
        }
      },
      "emerald" => {
        name: "Blue Slate",
        colors: %w[#DCE3EC #9BA9BD #3A445D #526A82 #202736],
        tokens: {
          "--ta-app-bg" => "#F1F4F8",
          "--ta-app-bg-strong" => "#E4E9F0",
          "--ta-surface" => "#FCFDFE",
          "--ta-surface-alt" => "#F5F7FA",
          "--ta-surface-subtle" => "#E9EDF3",
          "--ta-text" => "#202736",
          "--ta-text-muted" => "#4F5B70",
          "--ta-text-soft" => "#566174",
          "--ta-border" => "#CDD5E0",
          "--ta-border-strong" => "#A3AFC1",
          "--ta-control-border" => "#77849A",
          "--ta-accent" => "#3A445D",
          "--ta-accent-hover" => "#293248",
          "--ta-accent-soft" => "#E8ECF2",
          "--ta-accent-soft-strong" => "#DCE3EC",
          "--ta-accent-muted" => "#A6B1C2",
          "--ta-accent-contrast" => "#FFFFFF",
          "--ta-feature" => "#4D6078",
          "--ta-feature-soft" => "#E9EFF5"
        }
      },
      "sage" => {
        name: "Sage",
        colors: %w[#E6EEE3 #AFC4AF #48634E #66754E #2F3A31],
        tokens: {
          "--ta-app-bg" => "#F4F6F0",
          "--ta-app-bg-strong" => "#E7ECE2",
          "--ta-surface" => "#FEFFFC",
          "--ta-surface-alt" => "#F7F9F4",
          "--ta-surface-subtle" => "#EBF0E8",
          "--ta-text" => "#2F3A31",
          "--ta-text-muted" => "#506154",
          "--ta-text-soft" => "#566657",
          "--ta-border" => "#D3DDD0",
          "--ta-border-strong" => "#A8B9A8",
          "--ta-control-border" => "#718571",
          "--ta-accent" => "#48634E",
          "--ta-accent-hover" => "#344A39",
          "--ta-accent-soft" => "#E9F1E8",
          "--ta-accent-soft-strong" => "#DCE8DA",
          "--ta-accent-muted" => "#A8C0AA",
          "--ta-accent-contrast" => "#FFFFFF",
          "--ta-feature" => "#5B6644",
          "--ta-feature-soft" => "#EEF1E5"
        }
      },
      "sunset" => {
        name: "Sunset",
        colors: %w[#FDBA74 #F9A8D4 #BE185D #B9380B #451A35],
        tokens: {
          "--ta-app-bg" => "#FFF5ED",
          "--ta-app-bg-strong" => "#FDE9DB",
          "--ta-surface" => "#FFFCFA",
          "--ta-surface-alt" => "#FFF7F2",
          "--ta-surface-subtle" => "#FCECE3",
          "--ta-text" => "#451A35",
          "--ta-text-muted" => "#6B4F5E",
          "--ta-text-soft" => "#765C68",
          "--ta-border" => "#F0D1C2",
          "--ta-border-strong" => "#D6A99F",
          "--ta-control-border" => "#A56F78",
          "--ta-accent" => "#BE185D",
          "--ta-accent-hover" => "#9D174D",
          "--ta-accent-soft" => "#FDF2F8",
          "--ta-accent-soft-strong" => "#FCE7F3",
          "--ta-accent-muted" => "#F0A0C5",
          "--ta-accent-contrast" => "#FFFFFF",
          "--ta-feature" => "#B9380B",
          "--ta-feature-soft" => "#FFF0E8"
        }
      },
      "dark" => {
        name: "Midnight",
        colors: %w[#10141D #1D2531 #3A445D #AAB7D1 #F3F5F8],
        tokens: {
          "--ta-app-bg" => "#0F131B",
          "--ta-app-bg-strong" => "#0A0D13",
          "--ta-surface" => "#171D27",
          "--ta-surface-alt" => "#1D2531",
          "--ta-surface-subtle" => "#252F3D",
          "--ta-text" => "#F3F5F8",
          "--ta-text-muted" => "#C3CBD7",
          "--ta-text-soft" => "#ACB6C5",
          "--ta-border" => "#3C485A",
          "--ta-border-strong" => "#56647A",
          "--ta-control-border" => "#7A899F",
          "--ta-accent" => "#AAB7D1",
          "--ta-accent-hover" => "#C0CAE0",
          "--ta-accent-soft" => "#283247",
          "--ta-accent-soft-strong" => "#313D55",
          "--ta-accent-muted" => "#5B6B88",
          "--ta-accent-contrast" => "#111722",
          "--ta-feature" => "#E3B37C",
          "--ta-feature-soft" => "#36291E",
          "--ta-info" => "#7DD3FC",
          "--ta-info-soft" => "#0C3B55",
          "--ta-success" => "#6EE7B7",
          "--ta-success-soft" => "#0B3A2F",
          "--ta-success-contrast" => "#082019",
          "--ta-warning" => "#FCD34D",
          "--ta-warning-soft" => "#4A2A08",
          "--ta-danger" => "#FDA4AF",
          "--ta-danger-soft" => "#4A1120"
        }
      }
    }.freeze

    def self.all
      PRESETS.map do |key, config|
        Theme.new(
          key: key,
          name: config.fetch(:name),
          colors: config.fetch(:colors),
          tokens: STATUS_TOKENS.merge(config.fetch(:tokens))
        )
      end
    end

    def self.default_key
      "earth"
    end

    def self.fetch(key)
      normalized_key = normalize(key)
      all.find { |theme| theme.key == normalized_key }
    end

    def self.normalize(key)
      candidate = key.to_s

      PRESETS.key?(candidate) ? candidate : default_key
    end
  end
end
