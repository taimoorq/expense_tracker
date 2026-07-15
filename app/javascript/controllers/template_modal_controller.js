import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog"]
  static values = { allowBackdropClose: Boolean }

  connect() {
    this.previouslyFocusedElement = document.activeElement
    document.body.classList.add("overflow-hidden")

    requestAnimationFrame(() => this.focusInitialElement())
  }

  disconnect() {
    document.body.classList.remove("overflow-hidden")
    this.restoreFocus()
  }

  close() {
    const frame = this.element.closest("turbo-frame")

    if (frame) {
      frame.innerHTML = ""
      return
    }

    this.element.remove()
  }

  backdropClose(event) {
    if (event.target !== this.element) return
    if (this.hasAllowBackdropCloseValue && !this.allowBackdropCloseValue) return

    this.close()
  }

  trapFocus(event) {
    if (event.key !== "Tab" || !this.hasDialogTarget) return

    const focusable = this.focusableElements
    if (focusable.length === 0) {
      event.preventDefault()
      this.dialogTarget.focus()
      return
    }

    const first = focusable[0]
    const last = focusable[focusable.length - 1]

    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }

  focusInitialElement() {
    if (!this.hasDialogTarget) return

    const autofocus = this.dialogTarget.querySelector("[autofocus]")
    const closeButton = this.dialogTarget.querySelector("[data-modal-initial-focus]")
    const target = autofocus || closeButton || this.focusableElements[0] || this.dialogTarget
    target.focus({ preventScroll: true })
  }

  restoreFocus() {
    if (this.focusRestored) return

    this.focusRestored = true
    if (this.previouslyFocusedElement?.isConnected) {
      requestAnimationFrame(() => this.previouslyFocusedElement.focus({ preventScroll: true }))
    }
  }

  get focusableElements() {
    if (!this.hasDialogTarget) return []

    return Array.from(
      this.dialogTarget.querySelectorAll(
        "a[href], button:not([disabled]), input:not([disabled]):not([type='hidden']), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex='-1'])"
      )
    ).filter((element) => !element.hidden && element.getAttribute("aria-hidden") !== "true")
  }
}
