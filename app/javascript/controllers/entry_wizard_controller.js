import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "sourceMode",
    "oneTimePanel",
    "existingPanel",
    "recurringLink",
    "recurringStatus",
    "extraOccurrencePanel",
    "extraOccurrence",
    "section",
    "status",
    "date",
    "category",
    "payee",
    "sourceAccount",
    "destinationAccount",
    "destinationGroup",
    "account",
    "planned",
    "actual",
    "need",
    "notes",
    "sourceAccountLabel",
    "payeeLabel",
    "impactAmount",
    "monthImpact",
    "accountImpact",
    "statusImpact",
    "error",
    "errorSummary",
    "templateEnabled",
    "templateFields",
    "templateType",
    "templateDueDay",
    "templateCadence",
    "templateWeekendAdjustment",
    "templateEndsOn",
    "templateDayOne",
    "templateDayTwo",
    "templateKind",
    "templateBillingFrequency",
    "templateTotalDue",
    "templateAmountPaid",
    "payScheduleFields",
    "payScheduleSecondDayFields",
    "monthlyBillFields",
    "paymentPlanFields",
    "submitButton",
    "submitLabel",
    "cancelButton"
  ]

  static values = {
    supportedTemplateTypes: Object,
    monthLabel: String
  }

  connect() {
    this.submitting = false
    this.syncSourceMode()
    this.update()

    if (this.hasErrorSummaryTarget && this.errorSummaryTarget.dataset.serverErrors === "true") {
      requestAnimationFrame(() => this.errorSummaryTarget.focus())
    }
  }

  chooseSourceMode() {
    this.syncSourceMode()
    this.update()
  }

  syncSourceMode() {
    const existingMode = this.sourceModeTargets.find((target) => target.checked)?.value === "existing"

    if (this.hasOneTimePanelTarget) this.oneTimePanelTarget.classList.toggle("hidden", existingMode)
    if (this.hasExistingPanelTarget) this.existingPanelTarget.classList.toggle("hidden", !existingMode)
    if (this.hasRecurringLinkTarget) this.recurringLinkTarget.disabled = !existingMode
    if (this.hasTemplateEnabledTarget) this.templateEnabledTarget.disabled = existingMode

    if (this.hasExtraOccurrencePanelTarget) this.extraOccurrencePanelTarget.classList.add("hidden")

    if (this.hasExtraOccurrenceTarget) {
      this.extraOccurrenceTarget.checked = false
      this.extraOccurrenceTarget.disabled = true
    }
  }

  prefillRecurring() {
    if (!this.hasRecurringLinkTarget) return

    const option = this.recurringLinkTarget.selectedOptions[0]
    if (!option?.value) {
      this.setRecurringStatus("Choose a recurring item to fill the entry.", false)
      this.update()
      return
    }

    let prefill = {}
    try {
      prefill = JSON.parse(option.dataset.prefill || "{}")
    } catch (_error) {
      prefill = {}
    }

    this.assignValue("section", prefill.section)
    this.assignValue("status", prefill.status)
    this.assignValue("date", prefill.occurred_on)
    this.assignValue("category", prefill.category)
    this.assignValue("payee", prefill.payee)
    this.assignValue("planned", prefill.planned_amount)
    this.assignValue("actual", prefill.actual_amount)
    this.assignValue("sourceAccount", prefill.source_account_id)
    this.assignValue("destinationAccount", prefill.destination_account_id)
    this.assignValue("account", prefill.account)
    this.assignValue("need", prefill.need_or_want)
    this.assignValue("notes", prefill.notes)

    const extraRequired = option.dataset.extraRequired === "true"
    this.setRecurringStatus(option.dataset.statusLabel || "Recurring details added.", extraRequired)
    this.update()
  }

  setRecurringStatus(message, extraRequired) {
    if (this.hasRecurringStatusTarget) this.recurringStatusTarget.textContent = message
    if (this.hasExtraOccurrencePanelTarget) this.extraOccurrencePanelTarget.classList.toggle("hidden", !extraRequired)
    if (this.hasExtraOccurrenceTarget) {
      this.extraOccurrenceTarget.disabled = !extraRequired
      if (!extraRequired) this.extraOccurrenceTarget.checked = false
    }
  }

  update() {
    this.syncAccountLabels()
    this.syncDestinationVisibility()
    this.syncAccountFallback()
    this.syncRecurringStatus()
    this.updateTemplateOptions()
    this.updateTemplateFields()
    this.updateImpact()
    this.updateSubmitLabel()
    this.clearError()
  }

  syncAccountLabels() {
    const section = this.valueFor("section")
    const sourceLabel = section === "income" ? "Deposited to" : (section === "debt" ? "Paid from" : "Paid from or charged to")
    const payeeLabel = section === "income" ? "Paid by" : "Payee"

    if (this.hasSourceAccountLabelTarget) this.sourceAccountLabelTarget.textContent = sourceLabel
    if (this.hasPayeeLabelTarget) this.payeeLabelTarget.textContent = payeeLabel
  }

  syncDestinationVisibility() {
    if (!this.hasDestinationGroupTarget) return

    const section = this.valueFor("section")
    const destinationSelected = Boolean(this.valueFor("destinationAccount"))
    const visible = ["debt", "manual"].includes(section) || destinationSelected
    this.destinationGroupTarget.classList.toggle("hidden", !visible)
  }

  syncAccountFallback() {
    if (!this.hasAccountTarget || !this.hasSourceAccountTarget) return

    const selectedName = this.selectedOptionLabel(this.sourceAccountTarget)
    if (selectedName) this.accountTarget.value = selectedName
  }

  syncRecurringStatus() {
    if (!this.hasRecurringLinkTarget || this.recurringLinkTarget.disabled) return

    const option = this.recurringLinkTarget.selectedOptions[0]
    if (!option?.value) return

    this.setRecurringStatus(option.dataset.statusLabel || "Recurring details added.", option.dataset.extraRequired === "true")
  }

  updateImpact() {
    const actualValue = this.valueFor("actual")
    const amount = this.numberFor(actualValue !== "" ? actualValue : this.valueFor("planned"))
    const status = this.valueFor("status")
    const section = this.valueFor("section")
    const contributes = status !== "skipped" && amount !== 0
    const signedMonthAmount = section === "income" ? amount : -amount

    if (this.hasImpactAmountTarget) this.impactAmountTarget.textContent = this.formatCurrency(amount)

    if (this.hasMonthImpactTarget) {
      if (!contributes) {
        this.monthImpactTarget.textContent = `No change to ${this.monthLabelValue}`
      } else if (signedMonthAmount > 0) {
        this.monthImpactTarget.textContent = `Adds ${this.formatCurrency(amount)} to money available in ${this.monthLabelValue}`
      } else {
        this.monthImpactTarget.textContent = `Uses ${this.formatCurrency(amount)} from money available in ${this.monthLabelValue}`
      }
    }

    if (this.hasAccountImpactTarget) {
      const source = this.hasSourceAccountTarget ? this.selectedOptionLabel(this.sourceAccountTarget) : ""
      const destination = this.hasDestinationAccountTarget ? this.selectedOptionLabel(this.destinationAccountTarget) : ""
      const lines = []

      if (!contributes) {
        lines.push("No linked account balance change")
      } else {
        if (source) lines.push(`${source} ${section === "income" ? "+" : "−"}${this.formatCurrency(amount)}`)
        if (destination) lines.push(`${destination} +${this.formatCurrency(amount)}`)
        if (!source && !destination) lines.push("No saved account linked yet")
      }

      this.accountImpactTarget.textContent = lines.join(" · ")
    }

    if (this.hasStatusImpactTarget) {
      this.statusImpactTarget.textContent = {
        planned: "Planned: updates the month plan, not current account balances.",
        paid: "Paid: updates the month and linked account balances.",
        skipped: "Skipped: stays visible without changing totals or balances."
      }[status] || "Choose a status to see its effect."
    }
  }

  toggleTemplateFields() {
    this.updateTemplateOptions()
    this.updateTemplateFields()
    this.updateSubmitLabel()
    this.clearError()
  }

  updateTemplateOptions() {
    if (!this.hasTemplateTypeTarget) return

    const supportedTypes = this.supportedTemplateTypesValue[this.valueFor("section")] || []
    Array.from(this.templateTypeTarget.options).forEach((option) => {
      if (!option.value) return

      const supported = supportedTypes.includes(option.value)
      option.hidden = !supported
      option.disabled = !supported
    })

    if (this.templateTypeTarget.value && !supportedTypes.includes(this.templateTypeTarget.value)) {
      this.templateTypeTarget.value = ""
    }
  }

  updateTemplateFields() {
    const enabled = this.templateEnabled()
    const templateType = this.hasTemplateTypeTarget ? this.templateTypeTarget.value : ""

    if (this.hasTemplateFieldsTarget) this.templateFieldsTarget.classList.toggle("hidden", !enabled)
    if (this.hasPayScheduleFieldsTarget) this.payScheduleFieldsTarget.classList.toggle("hidden", !enabled || templateType !== "pay_schedule")
    if (this.hasMonthlyBillFieldsTarget) this.monthlyBillFieldsTarget.classList.toggle("hidden", !enabled || templateType !== "monthly_bill")
    if (this.hasPaymentPlanFieldsTarget) this.paymentPlanFieldsTarget.classList.toggle("hidden", !enabled || templateType !== "payment_plan")

    if (this.hasPayScheduleSecondDayFieldsTarget) {
      const show = enabled && templateType === "pay_schedule" && this.valueFor("templateCadence") === "semimonthly"
      this.payScheduleSecondDayFieldsTarget.classList.toggle("hidden", !show)
    }

    if (enabled) this.deriveRecurringDates()
  }

  deriveRecurringDates() {
    const dateValue = this.valueFor("date")
    if (!dateValue) return

    const day = Number(dateValue.split("-")[2])
    if (this.hasTemplateDueDayTarget && !this.templateDueDayTarget.value) this.templateDueDayTarget.value = day
    if (this.hasTemplateDayOneTarget && !this.templateDayOneTarget.value) this.templateDayOneTarget.value = day
  }

  suggestBillingMonths() {
    if (!this.hasTemplateBillingFrequencyTarget) return

    const frequency = this.templateBillingFrequencyTarget.value
    const dateMonth = Number((this.valueFor("date") || `${new Date().getFullYear()}-${new Date().getMonth() + 1}-01`).split("-")[1])
    const monthSequence = (count, step) => Array.from({ length: count }, (_, index) => ((dateMonth - 1 + (index * step)) % 12) + 1)
    const suggestions = {
      monthly: monthSequence(12, 1),
      quarterly: monthSequence(4, 3),
      semiannual: monthSequence(2, 6),
      annual: [dateMonth]
    }[frequency] || []

    this.element.querySelectorAll('input[name="planning_template[billing_months][]"]').forEach((checkbox) => {
      if (checkbox.type === "checkbox") checkbox.checked = suggestions.includes(Number(checkbox.value))
    })

    this.update()
  }

  validateSubmit(event) {
    if (this.submitting) {
      event.preventDefault()
      return
    }

    const validation = this.validationError()
    if (!validation) return

    event.preventDefault()
    this.fail(validation.message, validation.target)
  }

  validationError() {
    if (!this.valueFor("date")) return { message: "Choose a date for this entry.", target: this.dateTarget }
    if (!this.valueFor("category")) return { message: "Choose a category so this entry is easy to understand later.", target: this.categoryTarget }
    if (!this.valueFor("payee")) return { message: "Enter who this entry is with.", target: this.payeeTarget }
    if (!this.valueFor("planned") && !this.valueFor("actual")) return { message: "Enter an amount.", target: this.plannedTarget }

    if (this.valueFor("sourceAccount") && this.valueFor("sourceAccount") === this.valueFor("destinationAccount")) {
      return { message: "Money goes to must be a different account from Money comes from.", target: this.destinationAccountTarget }
    }

    if (this.existingMode()) {
      if (!this.valueFor("recurringLink")) return { message: "Choose the recurring item to use.", target: this.recurringLinkTarget }
      if (this.extraOccurrenceRequired() && !this.extraOccurrenceTarget.checked) {
        return { message: "Confirm that this is an extra occurrence before adding it.", target: this.extraOccurrenceTarget }
      }
    }

    if (this.templateEnabled()) {
      if (this.valueFor("destinationAccount")) {
        return { message: "A new recurring item cannot carry the Money goes to account yet. Save this as one-time or link an existing credit card.", target: this.destinationAccountTarget }
      }
      if (!this.valueFor("templateType")) return { message: "Choose what should repeat.", target: this.templateTypeTarget }
      if (this.usesDueDayTemplateType() && !this.valueFor("templateDueDay")) return { message: "Enter the day of month.", target: this.templateDueDayTarget }
      if (this.valueFor("templateType") === "payment_plan" && !this.valueFor("templateTotalDue")) return { message: "Enter the total due for this payment plan.", target: this.templateTotalDueTarget }
      if (this.valueFor("templateType") === "pay_schedule" && this.valueFor("templateCadence") === "semimonthly" && !this.valueFor("templateDayTwo")) {
        return { message: "Enter the second pay day.", target: this.templateDayTwoTarget }
      }
    }

    return null
  }

  submitStart() {
    this.submitting = true
    this.setPendingState()
  }

  submitEnd(event) {
    if (event.detail?.success) return

    this.submitting = false
    this.setPendingState()
  }

  setPendingState() {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = this.submitting
      this.submitButtonTarget.setAttribute("aria-busy", this.submitting ? "true" : "false")
    }
    if (this.hasCancelButtonTarget) this.cancelButtonTarget.disabled = this.submitting
    this.updateSubmitLabel()
  }

  updateSubmitLabel() {
    if (!this.hasSubmitLabelTarget) return

    if (this.submitting) {
      this.submitLabelTarget.textContent = "Adding entry…"
    } else if (this.templateEnabled()) {
      this.submitLabelTarget.textContent = "Add and save recurring"
    } else {
      this.submitLabelTarget.textContent = `Add to ${this.monthLabelValue}`
    }
  }

  fail(message, target) {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = message
      this.errorTarget.classList.remove("hidden")
    }
    target?.focus()
    return false
  }

  clearError() {
    if (!this.hasErrorTarget) return

    this.errorTarget.textContent = ""
    this.errorTarget.classList.add("hidden")
  }

  existingMode() {
    return this.sourceModeTargets.find((target) => target.checked)?.value === "existing"
  }

  extraOccurrenceRequired() {
    if (!this.hasRecurringLinkTarget) return false

    return this.recurringLinkTarget.selectedOptions[0]?.dataset.extraRequired === "true"
  }

  templateEnabled() {
    return this.hasTemplateEnabledTarget && !this.templateEnabledTarget.disabled && this.templateEnabledTarget.checked
  }

  usesDueDayTemplateType() {
    return ["subscription", "monthly_bill", "payment_plan"].includes(this.valueFor("templateType"))
  }

  assignValue(targetName, value) {
    const target = this.targetFor(targetName)
    if (!target) return

    target.value = value ?? ""
  }

  valueFor(targetName) {
    const target = this.targetFor(targetName)
    return target?.value?.trim() || ""
  }

  targetFor(targetName) {
    const capitalized = `${targetName.charAt(0).toUpperCase()}${targetName.slice(1)}`
    return this[`has${capitalized}Target`] ? this[`${targetName}Target`] : null
  }

  selectedOptionLabel(select) {
    if (!select?.value) return ""

    return select.selectedOptions?.[0]?.textContent?.trim() || ""
  }

  numberFor(value) {
    const parsed = Number(value)
    return Number.isFinite(parsed) ? parsed : 0
  }

  formatCurrency(amount) {
    return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(amount)
  }
}
