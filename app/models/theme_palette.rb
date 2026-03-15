class ThemePalette
  COOKIE_KEY = :expense_tracker_theme

  Theme = Struct.new(:key, :name, :colors, keyword_init: true) do
    def css_class
      "ta-theme-#{key}"
    end

    def meta_color
      colors.fetch(2)
    end

    def css_variables
      tone_1, tone_2, tone_3, tone_4, tone_5 = colors

      {
        "--ta-app-bg" => mix("#ffffff", tone_1, 0.30),
        "--ta-app-bg-strong" => mix("#ffffff", tone_1, 0.42),
        "--ta-surface" => mix("#ffffff", tone_1, 0.06),
        "--ta-surface-alt" => mix("#ffffff", tone_1, 0.16),
        "--ta-surface-subtle" => mix("#ffffff", tone_1, 0.28),
        "--ta-text" => tone_5,
        "--ta-text-muted" => tone_3,
        "--ta-text-soft" => tone_4,
        "--ta-border" => mix("#ffffff", tone_1, 0.58),
        "--ta-border-strong" => tone_1,
        "--ta-shadow-rgb" => rgb_triplet(tone_5),
        "--ta-accent" => tone_3,
        "--ta-accent-hover" => tone_5,
        "--ta-accent-soft" => mix("#ffffff", tone_1, 0.24),
        "--ta-accent-soft-strong" => mix("#ffffff", tone_1, 0.36),
        "--ta-accent-muted" => tone_1,
        "--ta-accent-contrast" => mix("#ffffff", tone_1, 0.04),
        "--ta-accent-rgb" => rgb_triplet(tone_3),
        "--ta-feature" => tone_4,
        "--ta-feature-soft" => mix("#ffffff", tone_4, 0.16),
        "--ta-info" => tone_2,
        "--ta-info-soft" => mix("#ffffff", tone_2, 0.16),
        "--ta-success" => tone_4,
        "--ta-success-soft" => mix("#ffffff", tone_4, 0.16),
        "--ta-warning" => tone_2,
        "--ta-warning-soft" => mix("#ffffff", tone_2, 0.14),
        "--ta-danger" => tone_5,
        "--ta-danger-soft" => mix("#ffffff", tone_5, 0.14)
      }
    end

    private

    def mix(base_hex, accent_hex, accent_weight)
      base_rgb = hex_to_rgb(base_hex)
      accent_rgb = hex_to_rgb(accent_hex)

      channels = base_rgb.zip(accent_rgb).map do |base_channel, accent_channel|
        ((base_channel * (1 - accent_weight)) + (accent_channel * accent_weight)).round
      end

      format("#%02x%02x%02x", *channels)
    end

    def rgb_triplet(hex)
      hex_to_rgb(hex).join(" ")
    end

    def hex_to_rgb(hex)
      sanitized = hex.delete("#")

      sanitized.scan(/../).map { |component| component.to_i(16) }
    end
  end

  PRESETS = {
    "earth" => {
      name: "Earth",
      colors: %w[#C3A995 #AB947E #6F5E53 #8A7968 #593D3B]
    },
    "indigo" => {
      name: "Indigo",
      colors: %w[#C7D2FE #93C5FD #4F46E5 #7C3AED #0F172A]
    },
    "emerald" => {
      name: "Emerald",
      colors: %w[#BBF7D0 #6EE7B7 #059669 #0F766E #052E2B]
    },
    "sage" => {
      name: "Sage",
      colors: %w[#F1F2EB #D8DAD3 #A4C2A5 #566246 #4A4A48]
    },
    "sunset" => {
      name: "Sunset",
      colors: %w[#FDBA74 #F9A8D4 #DB2777 #EA580C #4A044E]
    }
  }.freeze

  def self.all
    PRESETS.map do |key, config|
      Theme.new(key: key, name: config.fetch(:name), colors: config.fetch(:colors))
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
