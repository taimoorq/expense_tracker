import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row", "date", "payee", "reason", "status"]

  connect() {
    this.filter()
  }

  filter() {
    const dateValue = this.hasDateTarget ? this.dateTarget.value.trim() : ""
    const payeeValue = this.hasPayeeTarget ? this.payeeTarget.value.trim().toLowerCase() : ""
    const reasonValue = this.hasReasonTarget ? this.reasonTarget.value.trim().toLowerCase() : ""
    const statusValue = this.hasStatusTarget ? this.statusTarget.value.trim().toLowerCase() : ""

    this.rowTargets.forEach((row) => {
      const rowDate = (row.dataset.date || "").trim()
      const rowPayee = (row.dataset.payee || "").toLowerCase()
      const rowReason = (row.dataset.reason || "").toLowerCase()
      const rowStatus = (row.dataset.status || "").toLowerCase()

      const matchesDate = dateValue === "" || rowDate === dateValue
      const matchesPayee = payeeValue === "" || rowPayee.includes(payeeValue)
      const matchesReason = reasonValue === "" || rowReason.includes(reasonValue)
      const matchesStatus = statusValue === "" || rowStatus === statusValue

      row.dataset.searchHidden = matchesDate && matchesPayee && matchesReason && matchesStatus ? "false" : "true"
      this.applyVisibility(row)
    })
  }

  clearFilters() {
    if (this.hasDateTarget) this.dateTarget.value = ""
    if (this.hasPayeeTarget) this.payeeTarget.value = ""
    if (this.hasReasonTarget) this.reasonTarget.value = ""
    if (this.hasStatusTarget) this.statusTarget.value = ""

    this.filter()
  }

  applyVisibility(row) {
    row.classList.toggle("hidden", this.isHidden(row))
  }

  isHidden(row) {
    return row.dataset.searchHidden === "true" || row.dataset.pillHidden === "true"
  }
}
