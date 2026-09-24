import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger"]

  close() {
    this.element.open = false
  }

  closeOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  closeOnEscape(event) {
    if (!this.element.open) return
    event.preventDefault()
    this.close()
    this.triggerTarget.focus()
  }

  select(event) {
    if (event.target.closest("a")) {
      this.close()
      this.triggerTarget.focus()
    }
  }
}
