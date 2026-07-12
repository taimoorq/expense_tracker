import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["submitButton", "cancelButton", "auxButton", "submitLabel", "submitSpinner", "status"]

  static values = {
    defaultLabel: String,
    pendingLabel: { type: String, default: "Saving..." }
  }

  connect() {
    this.submitting = false
    this.submitButtonWasDisabled = null

    if (!this.hasDefaultLabelValue && this.hasSubmitLabelTarget) {
      this.defaultLabelValue = this.submitLabelTarget.textContent.trim()
    }

    this.sync()
  }

  submitStart() {
    if (this.submitting) return

    if (this.hasSubmitButtonTarget) {
      this.submitButtonWasDisabled = this.submitButtonTarget.disabled
    }

    this.submitting = true
    this.sync()
  }

  submitEnd(event) {
    if (event.detail?.success) return

    this.submitting = false
    this.sync()
    this.submitButtonWasDisabled = null
  }

  sync() {
    if (this.hasSubmitButtonTarget) {
      if (this.submitting) {
        this.submitButtonTarget.disabled = true
      } else if (this.submitButtonWasDisabled !== null) {
        this.submitButtonTarget.disabled = this.submitButtonWasDisabled
      }

      this.submitButtonTarget.setAttribute("aria-busy", this.submitting ? "true" : "false")
    }

    if (this.hasCancelButtonTarget) {
      this.cancelButtonTarget.disabled = this.submitting
    }

    this.auxButtonTargets.forEach((button) => {
      button.disabled = this.submitting
    })

    if (this.hasSubmitLabelTarget) {
      this.submitLabelTarget.textContent = this.submitting ? this.pendingLabelValue : this.defaultLabelValue
    }

    if (this.hasSubmitSpinnerTarget) {
      this.submitSpinnerTarget.classList.toggle("hidden", !this.submitting)
    }

    this.statusTargets.forEach((status) => {
      status.classList.toggle("hidden", !this.submitting)
      status.setAttribute("aria-hidden", this.submitting ? "false" : "true")
    })
  }
}
