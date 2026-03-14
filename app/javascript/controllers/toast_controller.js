import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { timeout: Number }

  connect() {
    const duration = this.timeoutValue || 4500
    this.timeout = window.setTimeout(() => this.close(), duration)
  }

  disconnect() {
    this.clearTimeout()
  }

  close() {
    this.clearTimeout()
    this.element.remove()
  }

  clearTimeout() {
    if (!this.timeout) return

    window.clearTimeout(this.timeout)
    this.timeout = null
  }
}