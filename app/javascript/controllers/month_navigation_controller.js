import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static allowedTabs = ["timeline", "breakdown", "entries", "calendar"]

  static targets = ["link"]
  static values = {
    currentTab: String
  }

  connect() {
    this.updateLinks()
  }

  sync(event) {
    const nextTab = event.detail?.name
    if (!nextTab) return
    if (!this.constructor.allowedTabs.includes(nextTab)) return

    this.currentTabValue = nextTab
    this.updateLinks()
  }

  updateLinks() {
    const activeTab = this.currentTabValue || "timeline"

    this.linkTargets.forEach((link) => {
      const urls = this.parseUrls(link.dataset.tabUrls)
      const href = urls?.[activeTab]

      if (href) {
        link.href = href
      }
    })
  }

  parseUrls(value) {
    if (!value) return null

    try {
      return JSON.parse(value)
    } catch (_error) {
      return null
    }
  }
}
