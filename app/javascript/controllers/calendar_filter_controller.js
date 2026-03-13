import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["filter", "day", "chip", "count", "empty"]

  connect() {
    this.activeGroups = new Set()
    this.refresh()
  }

  toggle(event) {
    const value = event.currentTarget.dataset.value
    if (!value) return

    if (value === "all") {
      this.activeGroups.clear()
    } else if (this.activeGroups.has(value)) {
      this.activeGroups.delete(value)
    } else {
      this.activeGroups.add(value)
    }

    this.refresh()
  }

  refresh() {
    const noFilters = this.activeGroups.size === 0

    this.filterTargets.forEach((button) => {
      const value = button.dataset.value
      const isActive = value === "all" ? noFilters : this.activeGroups.has(value)

      button.setAttribute("aria-pressed", String(isActive))
      button.classList.toggle("ring-2", isActive)
      button.classList.toggle("ring-offset-1", isActive)
      button.classList.toggle("ring-slate-300", isActive)
      button.classList.toggle("opacity-60", !isActive && !noFilters && value !== "all")
    })

    this.dayTargets.forEach((day) => {
      const chips = this.chipTargets.filter((chip) => chip.closest('[data-calendar-filter-target="day"]') === day)
      const visibleCount = chips.reduce((count, chip) => {
        const matches = noFilters || this.activeGroups.has((chip.dataset.value || "").toLowerCase())
        chip.classList.toggle("hidden", !matches)
        return matches ? count + 1 : count
      }, 0)

      const countBadge = day.querySelector('[data-calendar-filter-target="count"]')
      const emptyState = day.querySelector('[data-calendar-filter-target="empty"]')

      if (countBadge) {
        countBadge.textContent = `${visibleCount} ${visibleCount === 1 ? "entry" : "entries"}`
        countBadge.classList.toggle("hidden", visibleCount === 0)
      }

      if (emptyState) {
        emptyState.classList.toggle("hidden", visibleCount !== 0)
      }
    })
  }
}
