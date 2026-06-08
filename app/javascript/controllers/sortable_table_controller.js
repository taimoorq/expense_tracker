import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["header", "row"]

  sort(event) {
    const header = event.currentTarget.closest("[data-sortable-table-target~='header']")
    if (!header) return

    const key = header.dataset.sortableTableKey
    if (!key) return

    const type = header.dataset.sortableTableType || "text"
    const direction = this.nextDirection(header)

    this.sortRows(key, type, direction)
    this.updateHeaders(header, direction)
  }

  nextDirection(header) {
    const currentDirection = header.dataset.sortableTableDirection || "none"
    const defaultDirection = header.dataset.sortableTableDefaultDirection || "asc"

    if (currentDirection === "none") return defaultDirection
    return currentDirection === "asc" ? "desc" : "asc"
  }

  sortRows(key, type, direction) {
    const rows = this.rowTargets.map((row, index) => ({
      row,
      index,
      sortValue: this.sortValue(row, key, type)
    }))

    rows.sort((left, right) => {
      const missingComparison = this.compareMissing(left.sortValue, right.sortValue)
      if (missingComparison !== 0) return missingComparison

      const valueComparison = this.compareValues(left.sortValue.value, right.sortValue.value, type)
      if (valueComparison === 0) return left.index - right.index

      return direction === "asc" ? valueComparison : -valueComparison
    })

    rows.forEach(({ row }) => row.parentElement.appendChild(row))
  }

  sortValue(row, key, type) {
    const rawValue = row.getAttribute(`data-sort-${key}-value`) || ""
    const normalizedValue = rawValue.trim()

    return {
      missing: normalizedValue === "",
      value: this.normalizedValue(normalizedValue, type)
    }
  }

  normalizedValue(value, type) {
    if (type === "number") {
      const numericValue = Number.parseFloat(value.replace(/[^0-9.-]/g, ""))
      return Number.isNaN(numericValue) ? null : numericValue
    }

    if (type === "date") {
      const timestamp = Date.parse(value)
      return Number.isNaN(timestamp) ? null : timestamp
    }

    return value.toLocaleLowerCase()
  }

  compareMissing(left, right) {
    if (left.missing && right.missing) return 0
    if (left.missing) return 1
    if (right.missing) return -1
    if (left.value === null && right.value === null) return 0
    if (left.value === null) return 1
    if (right.value === null) return -1

    return 0
  }

  compareValues(left, right, type) {
    if (type === "number" || type === "date") {
      return left - right
    }

    return left.localeCompare(right, undefined, { numeric: true, sensitivity: "base" })
  }

  updateHeaders(activeHeader, direction) {
    this.headerTargets.forEach((header) => {
      const active = header === activeHeader
      const nextDirection = active ? direction : "none"

      header.dataset.sortableTableDirection = nextDirection
      header.setAttribute("aria-sort", this.ariaSortValue(nextDirection))
    })
  }

  ariaSortValue(direction) {
    if (direction === "asc") return "ascending"
    if (direction === "desc") return "descending"

    return "none"
  }
}
