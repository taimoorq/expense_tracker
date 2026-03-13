import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["shell", "expandIcon", "collapseIcon"]

  connect() {
    const stored = localStorage.getItem("expense-tracker.sidebar.collapsed")
    const collapsed = stored == null ? true : stored === "true"
    this.applyState(collapsed)
  }

  toggle() {
    this.applyState(!this.collapsed)
  }

  applyState(collapsed) {
    this.collapsed = collapsed

    this.shellTarget.classList.toggle("ta-shell-collapsed", collapsed)
    this.shellTarget.classList.toggle("ta-shell-expanded", !collapsed)

    if (this.hasExpandIconTarget) this.expandIconTarget.classList.toggle("hidden", !collapsed)
    if (this.hasCollapseIconTarget) this.collapseIconTarget.classList.toggle("hidden", collapsed)

    localStorage.setItem("expense-tracker.sidebar.collapsed", String(collapsed))
  }
}
