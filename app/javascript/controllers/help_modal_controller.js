import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["backdrop", "dialog", "title", "content", "closeButton"]

  open(event) {
    event.preventDefault()
    const title = event.currentTarget.dataset.helpTitle || "Help"
    const body = event.currentTarget.dataset.helpBody || "No help text available."

    this.titleTarget.textContent = title
    this.contentTarget.textContent = body
    this.previouslyFocusedElement = document.activeElement
    this.backdropTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
    requestAnimationFrame(() => this.closeButtonTarget.focus({ preventScroll: true }))
  }

  close() {
    this.backdropTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
    if (this.previouslyFocusedElement?.isConnected) {
      requestAnimationFrame(() => this.previouslyFocusedElement.focus({ preventScroll: true }))
    }
  }

  backdropClick(event) {
    if (event.target === this.backdropTarget) this.close()
  }

  closeOnEsc(event) {
    if (event.key === "Escape" && !this.backdropTarget.classList.contains("hidden")) this.close()
  }

  trapFocus(event) {
    if (event.key !== "Tab" || this.backdropTarget.classList.contains("hidden")) return

    const focusable = Array.from(
      this.dialogTarget.querySelectorAll(
        "a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex='-1'])"
      )
    )

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
}
