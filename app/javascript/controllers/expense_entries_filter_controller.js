import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "expense-tracker.entries-filter"

export default class extends Controller {
  static targets = [
    "group",
    "row",
    "chip",
    "day",
    "empty",
    "date",
    "payee",
    "reason",
    "status",
    "category"
  ]

  connect() {
    this.restoreFromStorage()
    this.refresh()
  }

  filter() {
    this.saveToStorage()
    this.refresh()
  }

  restoreAndRefresh() {
    this.restoreFromStorage()
    this.refresh()
  }

  clearFilters() {
    if (this.hasDateTarget) this.dateTarget.value = ""
    if (this.hasPayeeTarget) this.payeeTarget.value = ""
    if (this.hasReasonTarget) this.reasonTarget.value = ""
    if (this.hasStatusTarget) this.statusTarget.value = ""
    if (this.hasCategoryTarget) this.categoryTarget.value = ""

    this.saveToStorage()
    this.refresh()
  }

  refresh() {
    const categoryValue = this.hasCategoryTarget ? this.categoryTarget.value.trim().toLowerCase() : ""
    const noCategoryFilter = categoryValue === ""
    const dateValue = this.hasDateTarget ? this.dateTarget.value.trim() : ""
    const payeeValue = this.hasPayeeTarget ? this.payeeTarget.value.trim().toLowerCase() : ""
    const reasonValue = this.hasReasonTarget ? this.reasonTarget.value.trim().toLowerCase() : ""
    const statusValue = this.hasStatusTarget ? this.statusTarget.value.trim().toLowerCase() : ""
    const filtersActive =
      !noCategoryFilter ||
      dateValue !== "" ||
      payeeValue !== "" ||
      reasonValue !== "" ||
      statusValue !== ""

    if (this.hasRowTarget) {
      this.filterRows(categoryValue, noCategoryFilter, dateValue, payeeValue, reasonValue, statusValue)
      this.updateGroups()
    }

    if (this.hasChipTarget) {
      this.filterChips(categoryValue, noCategoryFilter, dateValue, payeeValue, reasonValue, statusValue)
      this.updateDays()
    }

    if (this.hasEmptyTarget) {
      const visibleGroups = this.hasGroupTarget
        ? this.groupTargets.filter((group) => !group.classList.contains("hidden")).length
        : 0
      this.emptyTarget.classList.toggle("hidden", visibleGroups > 0)
    }

    if (this.hasGroupTarget) {
      this.syncExpandedGroups(filtersActive)
    }
  }

  filterRows(categoryValue, noCategoryFilter, dateValue, payeeValue, reasonValue, statusValue) {
    this.rowTargets.forEach((row) => {
      const rowValue = (row.dataset.value || "").toLowerCase()
      const matchesCategory = noCategoryFilter || rowValue === categoryValue
      const rowDate = (row.dataset.date || "").trim()
      const rowPayee = (row.dataset.payee || "").toLowerCase()
      const rowReason = (row.dataset.reason || "").toLowerCase()
      const rowStatus = (row.dataset.status || "").toLowerCase()

      const matchesDate = dateValue === "" || rowDate === dateValue
      const matchesPayee = payeeValue === "" || rowPayee.includes(payeeValue)
      const matchesReason = reasonValue === "" || rowReason.includes(reasonValue)
      const matchesStatus = statusValue === "" || rowStatus === statusValue

      row.dataset.pillHidden = matchesCategory ? "false" : "true"
      row.dataset.searchHidden =
        matchesDate && matchesPayee && matchesReason && matchesStatus ? "false" : "true"
      row.classList.toggle("hidden", row.dataset.searchHidden === "true" || row.dataset.pillHidden === "true")
    })
  }

  filterChips(categoryValue, noCategoryFilter, dateValue, payeeValue, reasonValue, statusValue) {
    this.chipTargets.forEach((chip) => {
      const chipValue = (chip.dataset.value || "").toLowerCase()
      const matchesCategory = noCategoryFilter || chipValue === categoryValue
      const chipDate = (chip.dataset.date || "").trim()
      const chipPayee = (chip.dataset.payee || "").toLowerCase()
      const chipReason = (chip.dataset.reason || "").toLowerCase()
      const chipStatus = (chip.dataset.status || "").toLowerCase()

      const matchesDate = dateValue === "" || chipDate === dateValue
      const matchesPayee = payeeValue === "" || chipPayee.includes(payeeValue)
      const matchesReason = reasonValue === "" || chipReason.includes(reasonValue)
      const matchesStatus = statusValue === "" || chipStatus === statusValue

      const visible = matchesCategory && matchesDate && matchesPayee && matchesReason && matchesStatus
      chip.classList.toggle("hidden", !visible)
    })
  }

  updateGroups() {
    this.groupTargets.forEach((group) => {
      const rows = Array.from(group.querySelectorAll("[data-expense-entries-filter-target='row']"))
      const totalRows = rows.length
      const visibleRows = rows.filter((row) => !row.classList.contains("hidden")).length

      group.classList.toggle("hidden", visibleRows === 0)

      const count = group.querySelector("[data-expense-entries-filter-target='groupCount']")
      if (count) {
        count.textContent =
          visibleRows === totalRows
            ? `${totalRows} item${totalRows === 1 ? "" : "s"}`
            : `${visibleRows} shown · ${totalRows} total`
        count.classList.toggle("bg-slate-200", visibleRows === totalRows)
        count.classList.toggle("text-slate-600", visibleRows === totalRows)
        count.classList.toggle("bg-amber-100", visibleRows !== totalRows)
        count.classList.toggle("text-amber-800", visibleRows !== totalRows)
      }
    })
  }

  updateDays() {
    if (!this.hasDayTarget) return

    this.dayTargets.forEach((day) => {
      const chips = this.chipTargets.filter(
        (chip) => chip.closest("[data-expense-entries-filter-target='day']") === day
      )
      const visibleCount = chips.filter((chip) => !chip.classList.contains("hidden")).length

      const countBadge = day.querySelector("[data-expense-entries-filter-target='count']")
      const emptyState = day.querySelector("[data-expense-entries-filter-target='empty']")

      if (countBadge) {
        countBadge.textContent = `${visibleCount} ${visibleCount === 1 ? "entry" : "entries"}`
        countBadge.classList.toggle("hidden", visibleCount === 0)
      }

      if (emptyState) {
        emptyState.classList.toggle("hidden", visibleCount !== 0)
      }
    })
  }

  syncExpandedGroups(filtersActive) {
    const collapsibleController = this.application.getControllerForElementAndIdentifier(
      this.element,
      "collapsible-groups"
    )
    if (!collapsibleController) return

    collapsibleController.withPersistenceSuspended(() => {
      if (filtersActive) {
        this.groupTargets.forEach((group) => {
          if (!group.classList.contains("hidden")) {
            group.open = true
          }
        })
      } else {
        collapsibleController.restoreState()
      }
    })
  }

  restoreFromStorage() {
    try {
      const stored = localStorage.getItem(STORAGE_KEY)
      if (!stored) return

      const data = JSON.parse(stored)
      if (this.hasCategoryTarget && data.category) this.categoryTarget.value = data.category
      if (this.hasDateTarget && data.date) this.dateTarget.value = data.date
      if (this.hasPayeeTarget && data.payee) this.payeeTarget.value = data.payee
      if (this.hasReasonTarget && data.reason) this.reasonTarget.value = data.reason
      if (this.hasStatusTarget && data.status) this.statusTarget.value = data.status
    } catch (_e) {
      // ignore
    }
  }

  saveToStorage() {
    try {
      const data = {
        category: this.hasCategoryTarget ? this.categoryTarget.value : "",
        date: this.hasDateTarget ? this.dateTarget.value : "",
        payee: this.hasPayeeTarget ? this.payeeTarget.value : "",
        reason: this.hasReasonTarget ? this.reasonTarget.value : "",
        status: this.hasStatusTarget ? this.statusTarget.value : ""
      }
      localStorage.setItem(STORAGE_KEY, JSON.stringify(data))
    } catch (_e) {
      // ignore
    }
  }
}
