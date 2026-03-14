import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["filter", "group", "row", "empty", "date", "payee", "reason", "status"]

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

  filter() {
    this.refresh()
  }

  clearFilters() {
    this.activeGroups.clear()

    if (this.hasDateTarget) this.dateTarget.value = ""
    if (this.hasPayeeTarget) this.payeeTarget.value = ""
    if (this.hasReasonTarget) this.reasonTarget.value = ""
    if (this.hasStatusTarget) this.statusTarget.value = ""

    this.refresh()
  }

  refresh() {
    const noFilters = this.activeGroups.size === 0
    const dateValue = this.hasDateTarget ? this.dateTarget.value.trim() : ""
    const payeeValue = this.hasPayeeTarget ? this.payeeTarget.value.trim().toLowerCase() : ""
    const reasonValue = this.hasReasonTarget ? this.reasonTarget.value.trim().toLowerCase() : ""
    const statusValue = this.hasStatusTarget ? this.statusTarget.value.trim().toLowerCase() : ""

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
      const matchesPill = noFilters || this.activeGroups.has((row.dataset.value || "").toLowerCase())
      const rowDate = (row.dataset.date || "").trim()
      const rowPayee = (row.dataset.payee || "").toLowerCase()
      const rowReason = (row.dataset.reason || "").toLowerCase()
      const rowStatus = (row.dataset.status || "").toLowerCase()

      const matchesDate = dateValue === "" || rowDate === dateValue
      const matchesPayee = payeeValue === "" || rowPayee.includes(payeeValue)
      const matchesReason = reasonValue === "" || rowReason.includes(reasonValue)
      const matchesStatus = statusValue === "" || rowStatus === statusValue

      row.dataset.pillHidden = matchesPill ? "false" : "true"
      row.dataset.searchHidden = matchesDate && matchesPayee && matchesReason && matchesStatus ? "false" : "true"
      this.applyVisibility(row)
    })

    this.groupTargets.forEach((group) => {
      const rows = Array.from(group.querySelectorAll('[data-timeline-category-filter-target="row"]'))
      const totalRows = rows.length
      const visibleRows = rows.filter((row) => !this.isHidden(row)).length

      group.classList.toggle("hidden", visibleRows === 0)

      const count = group.querySelector('[data-timeline-category-filter-target="groupCount"]')
      if (count) {
        count.textContent = this.formatCount(visibleRows, totalRows)
        count.classList.toggle("bg-slate-200", visibleRows === totalRows)
        count.classList.toggle("text-slate-600", visibleRows === totalRows)
        count.classList.toggle("bg-amber-100", visibleRows !== totalRows)
        count.classList.toggle("text-amber-800", visibleRows !== totalRows)
      }
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

  formatCount(visibleRows, totalRows) {
    if (visibleRows === totalRows) {
      return this.pluralize(totalRows, "item")
    }

    return `${visibleRows} shown · ${totalRows} total`
  }

  pluralize(count, noun) {
    return `${count} ${noun}${count === 1 ? "" : "s"}`
  }
}
