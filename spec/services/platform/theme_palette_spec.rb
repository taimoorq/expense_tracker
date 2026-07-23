require "spec_helper"
require_relative "../../../app/services/platform/theme_palette"

RSpec.describe Platform::ThemePalette do
  describe ".all" do
    it "keeps normal text roles above WCAG AA contrast on every themed surface" do
      described_class.all.each do |theme|
        variables = theme.css_variables
        foregrounds = %w[--ta-text --ta-text-muted --ta-text-soft --ta-accent --ta-feature]
        backgrounds = %w[
          --ta-app-bg
          --ta-app-bg-strong
          --ta-surface
          --ta-surface-alt
          --ta-surface-subtle
          --ta-accent-soft
          --ta-accent-soft-strong
        ]

        foregrounds.product(backgrounds).each do |foreground_name, background_name|
          ratio = contrast_ratio(variables.fetch(foreground_name), variables.fetch(background_name))

          expect(ratio).to be >= 4.5,
            "expected #{theme.name} #{foreground_name} on #{background_name} to reach 4.5:1, got #{ratio.round(2)}:1"
        end
      end
    end

    it "keeps solid accent controls above WCAG AA text contrast" do
      described_class.all.each do |theme|
        variables = theme.css_variables

        %w[--ta-accent --ta-accent-hover].each do |background_name|
          ratio = contrast_ratio(variables.fetch("--ta-accent-contrast"), variables.fetch(background_name))

          expect(ratio).to be >= 4.5,
            "expected #{theme.name} accent label on #{background_name} to reach 4.5:1, got #{ratio.round(2)}:1"
        end
      end
    end

    it "keeps control boundaries and focus indicators above non-text contrast" do
      described_class.all.each do |theme|
        variables = theme.css_variables
        backgrounds = %w[--ta-app-bg --ta-app-bg-strong --ta-surface --ta-surface-alt --ta-surface-subtle]

        backgrounds.each do |background_name|
          control_ratio = contrast_ratio(variables.fetch("--ta-control-border"), variables.fetch(background_name))
          focus_ratio = contrast_ratio(variables.fetch("--ta-accent"), variables.fetch(background_name))

          expect(control_ratio).to be >= 3.0,
            "expected #{theme.name} control border on #{background_name} to reach 3:1, got #{control_ratio.round(2)}:1"
          expect(focus_ratio).to be >= 3.0,
            "expected #{theme.name} focus indicator on #{background_name} to reach 3:1, got #{focus_ratio.round(2)}:1"
        end
      end
    end

    it "uses stable accessible status colors across palettes" do
      described_class.all.each do |theme|
        variables = theme.css_variables

        %w[info success warning danger].each do |status|
          ratio = contrast_ratio(variables.fetch("--ta-#{status}"), variables.fetch("--ta-#{status}-soft"))

          expect(ratio).to be >= 4.5,
            "expected #{theme.name} #{status} text to reach 4.5:1, got #{ratio.round(2)}:1"
        end

        expect(contrast_ratio(variables.fetch("--ta-success-contrast"), variables.fetch("--ta-success"))).to be >= 4.5
      end
    end

    it "rebinds semantic aliases on the active theme element" do
      described_class.all.each do |theme|
        expect(theme.css_variables).to include(
          "--ta-canvas" => "var(--ta-app-bg)",
          "--ta-raised" => "var(--ta-surface)",
          "--ta-text-primary" => "var(--ta-text)",
          "--ta-text-secondary" => "var(--ta-text-muted)",
          "--ta-text-tertiary" => "var(--ta-text-soft)",
          "--ta-focus" => "var(--ta-accent)"
        )
      end
    end

    it "uses the requested replacement accents and exposes a dark color scheme" do
      expect(described_class.fetch("indigo").css_variables).to include(
        "--ta-accent" => "#5E5768",
        "--ta-color-scheme" => "light"
      )
      expect(described_class.fetch("emerald").css_variables).to include(
        "--ta-accent" => "#3A445D",
        "--ta-color-scheme" => "light"
      )
      expect(described_class.fetch("dark").css_variables).to include(
        "--ta-color-scheme" => "dark",
        "--ta-accent-contrast" => "#111722"
      )
    end
  end

  def contrast_ratio(foreground, background)
    foreground_luminance = relative_luminance(foreground)
    background_luminance = relative_luminance(background)

    ([ foreground_luminance, background_luminance ].max + 0.05) /
      ([ foreground_luminance, background_luminance ].min + 0.05)
  end

  def relative_luminance(hex)
    channels = hex.delete("#").scan(/../).map do |component|
      value = component.to_i(16) / 255.0

      value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
    end

    (0.2126 * channels.fetch(0)) + (0.7152 * channels.fetch(1)) + (0.0722 * channels.fetch(2))
  end
end
