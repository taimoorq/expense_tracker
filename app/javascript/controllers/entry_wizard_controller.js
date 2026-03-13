import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "step",
    "progress",
    "nextButton",
    "backButton",
    "submitButton",
    "section",
    "status",
    "category",
    "payee",
    "account",
    "date",
    "planned",
    "actual",
    "need",
    "notes",
    "summarySection",
    "summaryWho",
    "summaryWhen",
    "summaryAmounts",
    "summaryNotes",
    "error"
  ]

  connect() {
    this.index = 0
    this.showCurrentStep()
    this.updateSummary()
  }

  next() {
    if (!this.validateCurrentStep()) return
    this.index = Math.min(this.index + 1, this.stepTargets.length - 1)
    this.showCurrentStep()
  }

  back() {
    this.index = Math.max(this.index - 1, 0)
    this.showCurrentStep()
  }

  chooseSection(event) {
    const value = event.currentTarget.dataset.sectionValue
    if (this.hasSectionTarget) this.sectionTarget.value = value
    this.updateSummary()
    this.clearError()
  }

  updateSummary() {
    if (this.hasSummarySectionTarget) {
      const section = this.hasSectionTarget ? this.sectionTarget.value : ""
      const status = this.hasStatusTarget ? this.statusTarget.value : ""
      const need = this.hasNeedTarget ? this.needTarget.value : ""
      this.summarySectionTarget.textContent = [this.humanize(section), this.humanize(status), need].filter(Boolean).join(" • ") || "Not set"
    }

    if (this.hasSummaryWhoTarget) {
      const category = this.hasCategoryTarget ? this.categoryTarget.value.trim() : ""
      const payee = this.hasPayeeTarget ? this.payeeTarget.value.trim() : ""
      const account = this.hasAccountTarget ? this.accountTarget.value.trim() : ""
      this.summaryWhoTarget.textContent = [category, payee, account && `via ${account}`].filter(Boolean).join(" • ") || "Not set"
    }

    if (this.hasSummaryWhenTarget) {
      const date = this.hasDateTarget ? this.dateTarget.value : ""
      this.summaryWhenTarget.textContent = date || "Not set"
    }

    if (this.hasSummaryAmountsTarget) {
      const planned = this.formatCurrency(this.hasPlannedTarget ? this.plannedTarget.value : "")
      const actual = this.formatCurrency(this.hasActualTarget ? this.actualTarget.value : "")
      this.summaryAmountsTarget.textContent = `Planned: ${planned} • Actual: ${actual}`
    }

    if (this.hasSummaryNotesTarget) {
      const notes = this.hasNotesTarget ? this.notesTarget.value.trim() : ""
      this.summaryNotesTarget.textContent = notes || "No notes"
    }
  }

  showCurrentStep() {
    this.stepTargets.forEach((step, index) => {
      step.classList.toggle("hidden", index !== this.index)
    })

    if (this.hasProgressTarget) {
      this.progressTarget.textContent = `Step ${this.index + 1} of ${this.stepTargets.length}`
    }

    if (this.hasBackButtonTarget) {
      this.backButtonTarget.classList.toggle("hidden", this.index === 0)
    }

    if (this.hasNextButtonTarget) {
      this.nextButtonTarget.classList.toggle("hidden", this.index === this.stepTargets.length - 1)
    }

    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.classList.toggle("hidden", this.index !== this.stepTargets.length - 1)
    }

    this.updateSummary()
    this.clearError()
  }

  validateCurrentStep() {
    this.clearError()

    if (this.index === 0) {
      if (!this.sectionTarget.value) return this.fail("Choose the kind of entry you are adding.")
      if (!this.statusTarget.value) return this.fail("Choose a status for this entry.")
    }

    if (this.index === 1) {
      if (!this.categoryTarget.value.trim()) return this.fail("Add a category so this entry is easier to understand later.")
      if (!this.payeeTarget.value.trim()) return this.fail("Add who paid you or who you paid.")
    }

    if (this.index === 2) {
      const planned = this.plannedTarget.value.trim()
      const actual = this.actualTarget.value.trim()
      if (!this.dateTarget.value) return this.fail("Choose the date for this entry.")
      if (!planned && !actual) return this.fail("Enter at least a planned or actual amount.")
    }

    return true
  }

  fail(message) {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = message
      this.errorTarget.classList.remove("hidden")
    }
    return false
  }

  clearError() {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = ""
    this.errorTarget.classList.add("hidden")
  }

  humanize(value) {
    if (!value) return ""
    return value.replaceAll("_", " ").replace(/\b\w/g, (char) => char.toUpperCase())
  }

  formatCurrency(value) {
    const amount = Number(value)
    if (!Number.isFinite(amount) || value === "") return "$0.00"

    return new Intl.NumberFormat("en-US", {
      style: "currency",
      currency: "USD"
    }).format(amount)
  }
}
