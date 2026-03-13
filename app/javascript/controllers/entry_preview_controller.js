import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["planned", "actual", "effective"]

  connect() {
    this.update()
  }

  update() {
    const planned = this.parseAmount(this.plannedTarget?.value)
    const actual = this.parseAmount(this.actualTarget?.value)
    const effective = actual > 0 ? actual : planned

    this.effectiveTarget.textContent = new Intl.NumberFormat("en-US", {
      style: "currency",
      currency: "USD"
    }).format(effective)
  }

  parseAmount(value) {
    const parsed = Number(value)
    return Number.isFinite(parsed) ? parsed : 0
  }
}
