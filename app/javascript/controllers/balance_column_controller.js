import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["column", "button"]
  static values = { storageKey: String }

  connect() {
    try {
      this.shown = sessionStorage.getItem(this.storageKeyValue) === "true"
    } catch {
      this.shown = false
    }
    this.render()
  }

  toggle() {
    this.shown = !this.shown
    try {
      sessionStorage.setItem(this.storageKeyValue, String(this.shown))
    } catch {
      // The toggle still works when browser storage is unavailable.
    }
    this.render()
  }

  render() {
    this.columnTargets.forEach((column) => column.classList.toggle("hidden", !this.shown))
    this.buttonTarget.textContent = this.shown ? "Hide balances" : "Show balances"
    this.buttonTarget.setAttribute("aria-pressed", String(this.shown))
  }
}
