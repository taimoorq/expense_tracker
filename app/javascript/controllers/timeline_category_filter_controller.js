import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["filter", "group", "empty"]

  connect() {
    this.activeGroups = new Set()
    this.refresh()
  }

  toggle(event) {
    const group = event.currentTarget.dataset.group
    if (!group) return

    if (group === "all") {
      this.activeGroups.clear()
    } else if (this.activeGroups.has(group)) {
      this.activeGroups.delete(group)
    } else {
      this.activeGroups.add(group)
    }

    this.refresh()
  }

  refresh() {
    const noFilters = this.activeGroups.size === 0

    this.filterTargets.forEach((button) => {
      const group = button.dataset.group
      const isActive = group === "all" ? noFilters : this.activeGroups.has(group)

      button.setAttribute("aria-pressed", String(isActive))
      button.classList.toggle("ring-2", isActive)
      button.classList.toggle("ring-offset-1", isActive)
      button.classList.toggle("ring-slate-300", isActive && group === "all")
      button.classList.toggle("ring-emerald-300", isActive && group === "income")
      button.classList.toggle("ring-indigo-300", isActive && group === "recurring")
      button.classList.toggle("ring-sky-300", isActive && group === "bills")
      button.classList.toggle("ring-violet-300", isActive && group === "plans")
      button.classList.toggle("ring-amber-300", isActive && group === "cards")
      button.classList.toggle("ring-slate-400", isActive && group === "other")
      button.classList.toggle("opacity-60", !isActive && !noFilters && group !== "all")
    })

    let visibleGroups = 0

    this.groupTargets.forEach((group) => {
      const matches = noFilters || this.activeGroups.has(group.dataset.group)
      group.classList.toggle("hidden", !matches)
      if (matches) visibleGroups += 1
    })

    if (this.hasEmptyTarget) {
      this.emptyTarget.classList.toggle("hidden", visibleGroups > 0)
    }
  }
}
