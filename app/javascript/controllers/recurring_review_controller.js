import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["heading", "type", "billSchedule"]

  connect() {
    this.refresh()
  }

  refresh() {
    this.updateSchedule()
    // A late controller/frame connection must not interrupt someone typing.
    if (this.element.contains(document.activeElement) && document.activeElement.matches("input, textarea, select, button")) return
    const error = this.element.querySelector("[role='alert']")
    const heading = error || (this.hasHeadingTarget && this.headingTarget)
    if (heading) {
      heading.tabIndex = -1
      // Frame content can be clicked before frame-load; don't scroll a button away from the pointer.
      heading.focus({ preventScroll: !error })
    }
  }

  updateSchedule() {
    if (!this.hasTypeTarget || !this.hasBillScheduleTarget) return
    const bill = this.typeTarget.value === "monthly_bill"
    this.billScheduleTarget.hidden = !bill
    this.billScheduleTarget.open = bill
  }
}
