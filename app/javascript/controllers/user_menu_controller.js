import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "menu"]

  connect() {
    this.open = false
    this.sync()
  }

  toggle() {
    this.open = !this.open
    this.sync()
  }

  close() {
    if (!this.open) return

    this.open = false
    this.sync()
  }

  closeFromOutside(event) {
    if (this.element.contains(event.target)) return

    this.close()
  }

  closeOnEsc(event) {
    if (event.key !== "Escape") return

    this.close()
    this.buttonTarget.focus()
  }

  sync() {
    this.menuTarget.classList.toggle("hidden", !this.open)
    this.buttonTarget.setAttribute("aria-expanded", String(this.open))
  }
}
