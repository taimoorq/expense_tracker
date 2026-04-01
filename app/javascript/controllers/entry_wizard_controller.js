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
    "summaryRecurring",
    "summaryTemplate",
    "error",
    "recurringLink",
    "templateEnabled",
    "templateFields",
    "templateType",
    "templateDueDay",
    "templateCadence",
    "templateWeekendAdjustment",
    "templateDayOne",
    "templateDayTwo",
    "templateKind",
    "templateBillingFrequency",
    "templateTotalDue",
    "templateAmountPaid",
    "payScheduleFields",
    "payScheduleSecondDayFields",
    "monthlyBillFields",
    "paymentPlanFields"
  ]

  static values = {
    supportedTemplateTypes: Object
  }

  connect() {
    this.index = 0
    this.supportedTemplateTypesValue = {
      income: ["pay_schedule"],
      fixed: ["subscription", "monthly_bill"],
      variable: ["subscription", "monthly_bill"],
      debt: ["payment_plan"],
      manual: ["subscription", "monthly_bill", "payment_plan"],
      auto: ["subscription", "monthly_bill"],
      other: ["subscription", "monthly_bill"]
    }
    this.updateTemplateOptions()
    this.updateTemplateFields()
    this.showCurrentStep()
    this.updateSummary()
  }

  validateSubmit(event) {
    if (this.index !== this.stepTargets.length - 1) {
      event.preventDefault()
      this.fail("Finish the wizard steps before saving.")
      return
    }

    if (!this.validateCurrentStep()) {
      event.preventDefault()
    }
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
    this.syncTemplateOptions()
    this.updateSummary()
    this.clearError()
  }

  chooseAccount(event) {
    if (!this.hasAccountTarget) return

    this.accountTarget.value = event.currentTarget.dataset.accountValue || ""
    this.updateSummary()
    this.clearError()
  }

  syncTemplateOptions() {
    this.updateTemplateOptions()
    this.updateTemplateFields()
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

    if (this.hasSummaryRecurringTarget) {
      this.summaryRecurringTarget.textContent = this.recurringLinkSummary()
    }

    if (this.hasSummaryTemplateTarget) {
      this.summaryTemplateTarget.textContent = this.templateSummary()
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

    if (this.index === this.stepTargets.length - 1 && this.templateEnabled()) {
      if (!this.hasTemplateTypeTarget || !this.templateTypeTarget.value) {
        return this.fail("Choose which recurring transaction type to save.")
      }

      if ((this.usesDueDayTemplateType()) && (!this.hasTemplateDueDayTarget || !this.templateDueDayTarget.value)) {
        return this.fail("Add a due day for the recurring transaction.")
      }

      if (this.templateTypeTarget.value === "monthly_bill") {
        const expectedMonths = this.expectedBillingMonthCount()
        const selectedMonths = this.selectedBillingMonths().length

        if (selectedMonths !== expectedMonths) {
          return this.fail(`Choose ${expectedMonths} billing month${expectedMonths === 1 ? "" : "s"} for the monthly bill template.`)
        }
      }

      if (this.templateTypeTarget.value === "payment_plan" && (!this.hasTemplateTotalDueTarget || !this.templateTotalDueTarget.value.trim())) {
        return this.fail("Add the total due for the payment plan recurring transaction.")
      }

      if (this.templateTypeTarget.value === "pay_schedule" && this.hasTemplateCadenceTarget && this.templateCadenceTarget.value === "semimonthly") {
        if (!this.hasTemplateDayOneTarget || !this.templateDayOneTarget.value) {
          return this.fail("Add the first semimonthly pay day.")
        }

        if (!this.hasTemplateDayTwoTarget || !this.templateDayTwoTarget.value) {
          return this.fail("Add the second semimonthly pay day.")
        }
      }
    }

    return true
  }

  toggleTemplateFields() {
    if (this.hasTemplateFieldsTarget) {
      this.templateFieldsTarget.classList.toggle("hidden", !this.templateEnabled())
    }

    this.updateTemplateOptions()
    this.updateTemplateFields()
    this.clearError()
  }

  updateTemplateOptions() {
    if (!this.hasTemplateTypeTarget) return

    const supportedTypes = this.supportedTypesForCurrentSection()

    Array.from(this.templateTypeTarget.options).forEach((option) => {
      if (option.value === "") {
        option.hidden = false
        option.disabled = false
        return
      }

      const supported = supportedTypes.includes(option.value)
      option.hidden = !supported
      option.disabled = !supported
    })

    if (!supportedTypes.includes(this.templateTypeTarget.value)) {
      this.templateTypeTarget.value = ""
    }
  }

  updateTemplateFields() {
    const templateType = this.hasTemplateTypeTarget ? this.templateTypeTarget.value : ""

    if (this.hasPayScheduleFieldsTarget) {
      this.payScheduleFieldsTarget.classList.toggle("hidden", !this.templateEnabled() || templateType !== "pay_schedule")
    }

    if (this.hasMonthlyBillFieldsTarget) {
      this.monthlyBillFieldsTarget.classList.toggle("hidden", !this.templateEnabled() || templateType !== "monthly_bill")
    }

    if (this.hasPaymentPlanFieldsTarget) {
      this.paymentPlanFieldsTarget.classList.toggle("hidden", !this.templateEnabled() || templateType !== "payment_plan")
    }

    if (this.hasPayScheduleSecondDayFieldsTarget) {
      const showSecondDay = this.templateEnabled() && templateType === "pay_schedule" && this.hasTemplateCadenceTarget && this.templateCadenceTarget.value === "semimonthly"
      this.payScheduleSecondDayFieldsTarget.classList.toggle("hidden", !showSecondDay)
    }
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

  templateEnabled() {
    return this.hasTemplateEnabledTarget && this.templateEnabledTarget.checked
  }

  supportedTypesForCurrentSection() {
    const section = this.hasSectionTarget ? this.sectionTarget.value : ""
    return this.supportedTemplateTypesValue[section] || []
  }

  usesDueDayTemplateType() {
    if (!this.hasTemplateTypeTarget) return false
    return ["subscription", "monthly_bill", "payment_plan"].includes(this.templateTypeTarget.value)
  }

  templateSummary() {
    if (!this.templateEnabled()) return "One-off entry only"
    if (!this.hasTemplateTypeTarget || !this.templateTypeTarget.value) return "Save as recurring is on, but the recurring type is not chosen yet"

    const templateType = this.humanize(this.templateTypeTarget.value)

    if (this.templateTypeTarget.value === "pay_schedule") {
      const cadence = this.hasTemplateCadenceTarget ? this.humanize(this.templateCadenceTarget.value) : "Monthly"
      const dayOne = this.hasTemplateDayOneTarget && this.templateDayOneTarget.value ? `Day ${this.templateDayOneTarget.value}` : "first pay date"
      const dayTwo = this.hasTemplateDayTwoTarget && this.templateDayTwoTarget.value ? ` and day ${this.templateDayTwoTarget.value}` : ""
      return `${templateType} • ${cadence} • ${dayOne}${dayTwo}`
    }

    if (this.templateTypeTarget.value === "monthly_bill") {
      const kind = this.hasTemplateKindTarget ? this.humanize(this.templateKindTarget.value) : "Fixed Payment"
      const dueDay = this.hasTemplateDueDayTarget && this.templateDueDayTarget.value ? `Due day ${this.templateDueDayTarget.value}` : "Due day not set"
      const frequency = this.hasTemplateBillingFrequencyTarget ? this.humanize(this.templateBillingFrequencyTarget.value) : "Monthly"
      const months = this.selectedBillingMonths().map((month) => this.calendarMonthName(month)).join(", ")
      return `${templateType} • ${kind} • ${frequency} • ${months || "Months not set"} • ${dueDay}`
    }

    if (this.templateTypeTarget.value === "payment_plan") {
      const totalDue = this.hasTemplateTotalDueTarget ? this.formatCurrency(this.templateTotalDueTarget.value) : "$0.00"
      const dueDay = this.hasTemplateDueDayTarget && this.templateDueDayTarget.value ? `Due day ${this.templateDueDayTarget.value}` : "Due day not set"
      return `${templateType} • Total due ${totalDue} • ${dueDay}`
    }

    const dueDay = this.hasTemplateDueDayTarget && this.templateDueDayTarget.value ? `Due day ${this.templateDueDayTarget.value}` : "Due day not set"
    return `${templateType} • ${dueDay}`
  }

  recurringLinkSummary() {
    if (!this.hasRecurringLinkTarget || !this.recurringLinkTarget.value) return "No recurring link"

    const selectedOption = this.recurringLinkTarget.selectedOptions[0]
    const label = selectedOption ? selectedOption.textContent.trim() : "Linked recurring item"
    return `Linked to ${label}`
  }

  selectedBillingMonths() {
    return Array.from(this.element.querySelectorAll('input[name="planning_template[billing_months][]"]:checked'))
      .map((input) => Number(input.value))
      .filter((month) => Number.isInteger(month) && month >= 1 && month <= 12)
      .sort((left, right) => left - right)
  }

  expectedBillingMonthCount() {
    if (!this.hasTemplateBillingFrequencyTarget) return 12

    return {
      monthly: 12,
      quarterly: 4,
      semiannual: 2,
      annual: 1
    }[this.templateBillingFrequencyTarget.value] || 12
  }

  calendarMonthName(month) {
    return new Date(2000, month - 1, 1).toLocaleString("en-US", { month: "long" })
  }
}
