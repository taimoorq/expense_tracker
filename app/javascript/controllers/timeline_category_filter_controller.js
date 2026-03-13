import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["filter", "group", "row", "empty"]

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

    this.rowTargets.forEach((row) => {
      const matches = noFilters || this.activeGroups.has((row.dataset.value || "").toLowerCase())
      row.dataset.pillHidden = matches ? "false" : "true"
      this.applyVisibility(row)
    })

    this.groupTargets.forEach((group) => {
      const rows = Array.from(group.querySelectorAll('[data-timeline-category-filter-target="row"]'))
      const visibleRows = rows.filter((row) => !this.isHidden(row)).length
      group.classList.toggle("hidden", visibleRows === 0)
    })

    if (this.hasEmptyTarget) {
      const visibleGroups = this.groupTargets.filter((group) => !group.classList.contains("hidden")).length
      this.emptyTarget.classList.toggle("hidden", visibleGroups > 0)
    }
  }

  applyVisibility(row) {
    row.classList.toggle("hidden", this.isHidden(row))
  }

  isHidden(row) {
    return row.dataset.searchHidden === "true" || row.dataset.pillHidden === "true"
  }
}
