import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "swatches"]
  static values = { themes: Object }

  change() {
    const theme = this.themesValue[this.selectTarget.value]
    if (!theme) return

    this.applyTheme(theme)
    this.renderSwatches(theme)
    this.element.requestSubmit()
  }

  applyTheme(theme) {
    const body = document.body
    if (!body) return

    Object.values(this.themesValue).forEach((entry) => {
      body.classList.remove(entry.css_class)
    })

    body.classList.add(theme.css_class)

    Object.entries(theme.css_variables).forEach(([name, value]) => {
      body.style.setProperty(name, value)
    })

    const metaTheme = document.querySelector("meta[name='theme-color']")
    if (metaTheme) metaTheme.setAttribute("content", theme.meta_color)
  }

  renderSwatches(theme) {
    if (!this.hasSwatchesTarget) return

    this.swatchesTarget.setAttribute("aria-label", `${theme.name} palette`)
    this.swatchesTarget.innerHTML = theme.colors.map((color, index) => (
      `<span class="ta-theme-swatch" style="background-color: ${color}" title="${theme.name} color ${index + 1}: ${color}"></span>`
    )).join("")
  }
}
