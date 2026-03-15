import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["widget"]
  static values = { siteKey: String }

  connect() {
    this.beforeCache = this.resetWidget.bind(this)
    document.addEventListener("turbo:before-cache", this.beforeCache)
    this.scheduleRender()
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCache)
    this.stopPolling()
  }

  scheduleRender() {
    if (window.turnstile) {
      this.renderWidget()
      return
    }

    this.pollId = window.setInterval(() => {
      if (!window.turnstile) {
        return
      }

      this.stopPolling()
      this.renderWidget()
    }, 150)
  }

  renderWidget() {
    if (!this.hasWidgetTarget || this.widgetTarget.children.length > 0) {
      return
    }

    window.turnstile.render(this.widgetTarget, {
      sitekey: this.siteKeyValue,
      theme: "light"
    })
  }

  resetWidget() {
    if (!this.hasWidgetTarget) {
      return
    }

    this.widgetTarget.innerHTML = ""
  }

  stopPolling() {
    if (!this.pollId) {
      return
    }

    window.clearInterval(this.pollId)
    this.pollId = null
  }
}
