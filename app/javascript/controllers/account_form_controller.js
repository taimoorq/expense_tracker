import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["kind", "schedulePanel", "scheduleToggle", "scheduleInput"]

  connect() {
    this.syncScheduleFields()
  }

  kindChanged() {
    this.syncScheduleFields()
  }

  scheduleToggled() {
    this.syncScheduleFields()
  }

  syncScheduleFields() {
    if (!this.hasSchedulePanelTarget) return

    const isCreditCard = this.hasKindTarget && this.kindTarget.value === "credit_card"
    const scheduleEnabled = isCreditCard && this.hasScheduleToggleTarget && this.scheduleToggleTarget.checked

    this.schedulePanelTarget.classList.toggle("hidden", !isCreditCard)

    if (this.hasScheduleToggleTarget) {
      this.scheduleToggleTarget.disabled = !isCreditCard
    }

    this.scheduleInputTargets.forEach((input) => {
      input.disabled = !scheduleEnabled
    })
  }
}
