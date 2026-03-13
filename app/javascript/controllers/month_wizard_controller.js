import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["step", "progress", "backButton", "nextButton", "submitButton", "error", "workflow", "clonePanel", "sourceSelect", "cloneSummary", "stepIndicator", "choiceCard", "clonePreview", "previewTargetLabel", "previewSourceLabel", "previewEntryCount"]
  static values = { startStep: Number }

  connect() {
    this.index = this.hasStartStepValue ? this.startStepValue : 0
    this.showCurrentStep()
    this.refreshWorkflowState()
  }

  next() {
    this.clearError()

    if (this.index === 0) {
      if (!this.selectedWorkflow) {
        this.fail("Choose whether you want to clone a month or start fresh.")
        return
      }

      if (this.selectedWorkflow === "clone") {
        if (!this.hasSourceSelectTarget || !this.sourceSelectTarget.value) {
          this.fail("Choose a month to clone before continuing.")
          return
        }

        this.element.requestSubmit()
        return
      }
    }

    this.index = Math.min(this.index + 1, this.stepTargets.length - 1)
    this.showCurrentStep()
  }

  back() {
    this.clearError()
    this.index = Math.max(this.index - 1, 0)
    this.showCurrentStep()
  }

  workflowChanged() {
    this.clearError()
    this.refreshWorkflowState()
    this.showCurrentStep()
  }

  sourceChanged() {
    this.clearError()
    this.refreshWorkflowState()
  }

  showCurrentStep() {
    this.stepTargets.forEach((step, index) => {
      step.classList.toggle("hidden", index !== this.index)
    })

    this.updateStepIndicators()

    if (this.hasProgressTarget) {
      this.progressTarget.textContent = `Step ${this.index + 1} of ${this.stepTargets.length}`
    }

    if (this.hasBackButtonTarget) {
      this.backButtonTarget.classList.toggle("hidden", this.index === 0)
    }

    if (this.hasNextButtonTarget) {
      this.nextButtonTarget.classList.toggle("hidden", this.index !== 0)
      this.nextButtonTarget.textContent = this.selectedWorkflow === "clone" ? "Clone Month" : "Next"
    }

    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.classList.toggle("hidden", this.index === 0)
    }
  }

  refreshWorkflowState() {
    const cloning = this.selectedWorkflow === "clone"

    if (this.hasChoiceCardTarget) {
      this.choiceCardTargets.forEach((card, index) => {
        const shouldBeActive = this.workflowTargets[index]?.checked
        card.classList.toggle("ta-wizard-choice-active", shouldBeActive)
      })
    }

    if (this.hasClonePanelTarget) {
      this.clonePanelTarget.classList.toggle("hidden", !cloning)
    }

    if (this.hasCloneSummaryTarget) {
      if (!cloning) {
        this.cloneSummaryTarget.textContent = "Choose start fresh to continue to manual month details on the next step."
      } else if (this.hasSourceSelectTarget && this.sourceSelectTarget.value) {
        const selectedText = this.sourceSelectTarget.selectedOptions[0].textContent
        const [sourceLabel, targetLabel] = selectedText.split("→").map((part) => part.trim())
        this.cloneSummaryTarget.innerHTML = `Next will create <strong>${targetLabel}</strong> by copying entries from <strong>${sourceLabel}</strong>.`
      } else {
        this.cloneSummaryTarget.textContent = "Pick a source month to enable the quick clone path."
      }
    }

    if (this.hasClonePreviewTarget) {
      const shouldShowPreview = cloning && this.hasSourceSelectTarget && this.sourceSelectTarget.value
      this.clonePreviewTarget.classList.toggle("hidden", !shouldShowPreview)

      if (shouldShowPreview) {
        const option = this.sourceSelectTarget.selectedOptions[0]
        if (this.hasPreviewTargetLabelTarget) this.previewTargetLabelTarget.textContent = option.dataset.targetLabel || ""
        if (this.hasPreviewSourceLabelTarget) this.previewSourceLabelTarget.textContent = option.dataset.sourceLabel || ""
        if (this.hasPreviewEntryCountTarget) this.previewEntryCountTarget.textContent = option.dataset.entryCount || "0"
      }
    }
  }

  updateStepIndicators() {
    if (!this.hasStepIndicatorTarget) return

    this.stepIndicatorTargets.forEach((indicator, index) => {
      indicator.classList.toggle("ta-wizard-step-active", index === this.index)
      indicator.classList.toggle("ta-wizard-step-complete", index < this.index)
    })
  }

  fail(message) {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = message
      this.errorTarget.classList.remove("hidden")
    }
  }

  clearError() {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = ""
    this.errorTarget.classList.add("hidden")
  }

  get selectedWorkflow() {
    const selected = this.workflowTargets.find((input) => input.checked)
    return selected?.value
  }
}