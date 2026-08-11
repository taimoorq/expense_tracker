import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { active: Boolean, interval: { type: Number, default: 2000 } }

  connect() {
    this.schedule()
  }

  disconnect() {
    window.clearTimeout(this.timeout)
  }

  schedule() {
    if (!this.activeValue) return

    this.timeout = window.setTimeout(() => {
      if (!this.element.isConnected) return

      const frame = this.element.closest("turbo-frame")
      if (typeof frame?.reload === "function") frame.reload()
      this.schedule()
    }, this.intervalValue)
  }
}
