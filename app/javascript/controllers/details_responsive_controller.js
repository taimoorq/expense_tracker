import { Controller } from "@hotwired/stimulus"

// Opens a <details> element when viewport is at or above the given breakpoint.
// On smaller viewports, the details stays collapsed by default.
export default class extends Controller {
  static values = { expandAbove: { type: Number, default: 768 } }

  connect() {
    this.mediaQuery = window.matchMedia(`(min-width: ${this.expandAboveValue}px)`)
    this.updateOpen = this.updateOpen.bind(this)
    this.updateOpen()
    this.mediaQuery.addEventListener("change", this.updateOpen)
  }

  disconnect() {
    this.mediaQuery.removeEventListener("change", this.updateOpen)
  }

  updateOpen() {
    this.element.open = this.mediaQuery.matches
  }
}
