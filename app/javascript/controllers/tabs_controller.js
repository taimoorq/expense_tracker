import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel", "syncLink"]
  static values = {
    defaultTab: String,
    tabUrls: Object
  }

  connect() {
    const initial = this.defaultTabValue || this.tabTargets[0]?.dataset.tabName
    if (initial) this.show(initial, { updateLocation: false })
  }

  switch(event) {
    event.preventDefault()
    const { name } = event.params
    if (!name) return

    this.show(name)
  }

  show(name, { updateLocation = true } = {}) {
    this.tabTargets.forEach((tab) => {
      const isActive = tab.dataset.tabName === name
      tab.setAttribute("aria-selected", String(isActive))
      tab.tabIndex = isActive ? 0 : -1

      if (isActive) {
        tab.classList.add("ta-tab-active")
      } else {
        tab.classList.remove("ta-tab-active")
      }
    })

    this.panelTargets.forEach((panel) => {
      const isActive = panel.dataset.panelName === name
      panel.classList.toggle("hidden", !isActive)
    })

    this.syncLinks(name)

    if (updateLocation) {
      this.syncLocation(name)
    }

    document.dispatchEvent(new CustomEvent("tabs:switched", { bubbles: true, detail: { name } }))
  }

  syncLocation(name) {
    if (!this.hasTabUrlsValue) return

    const nextUrl = this.tabUrlsValue[name]
    if (!nextUrl) return

    window.history.replaceState(window.history.state, "", nextUrl)
  }

  syncLinks(name) {
    if (!this.hasSyncLinkTarget) return

    this.syncLinkTargets.forEach((link) => {
      const urls = this.parseUrls(link.dataset.tabUrls)
      const href = urls?.[name]

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
