import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["backdrop", "dialog", "title", "content"]

  open(event) {
    event.preventDefault()
    const title = event.currentTarget.dataset.helpTitle || "Help"
    const body = event.currentTarget.dataset.helpBody || "No help text available."

    this.titleTarget.textContent = title
    this.contentTarget.textContent = body
    this.backdropTarget.classList.remove("hidden")
    this.backdropTarget.classList.add("flex")
  }

  close() {
    this.backdropTarget.classList.add("hidden")
    this.backdropTarget.classList.remove("flex")
  }

  backdropClick(event) {
    if (event.target === this.backdropTarget) this.close()
  }

  closeOnEsc(event) {
    if (event.key === "Escape") this.close()
  }
}
