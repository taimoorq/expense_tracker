import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["submitButton", "cancelButton", "auxButton", "submitLabel", "submitSpinner"]

  static values = {
    defaultLabel: String,
    pendingLabel: { type: String, default: "Saving..." }
  }

  connect() {
    this.submitting = false

    if (!this.hasDefaultLabelValue && this.hasSubmitLabelTarget) {
      this.defaultLabelValue = this.submitLabelTarget.textContent.trim()
    }

    this.sync()
  }

  submitStart() {
    this.submitting = true
    this.sync()
  }

  submitEnd(event) {
    if (event.detail?.success) return

    this.submitting = false
    this.sync()
  }

  sync() {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = this.submitting
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
  }
}
