import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["flow", "destination", "destinationAccount"]

  connect() { this.sync() }

  sync() {
    const transfer = this.flowTarget.value === "transfer"
    this.destinationTarget.hidden = !transfer
    this.destinationAccountTarget.disabled = !transfer
    this.destinationAccountTarget.required = transfer
  }
}
