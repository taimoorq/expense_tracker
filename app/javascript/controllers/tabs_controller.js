import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = { defaultTab: String }

  connect() {
    const initial = this.defaultTabValue || this.tabTargets[0]?.dataset.tabName
    if (initial) this.show(initial)
  }

  switch(event) {
    event.preventDefault()
    const { name } = event.params
    if (!name) return

    this.show(name)
  }

  show(name) {
    this.tabTargets.forEach((tab) => {
      const isActive = tab.dataset.tabName === name
      tab.setAttribute("aria-selected", String(isActive))

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

    document.dispatchEvent(new CustomEvent("tabs:switched", { bubbles: true, detail: { name } }))
  }
}
