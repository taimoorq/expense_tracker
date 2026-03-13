import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropzone", "input", "fileName", "submit"]

  open(event) {
    if (event.target.closest("button") || event.target.closest("a")) return
    this.inputTarget.click()
  }

  dragOver(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.add("ta-upload-dropzone-active")
  }

  dragLeave(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.remove("ta-upload-dropzone-active")
  }

  drop(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.remove("ta-upload-dropzone-active")

    if (!event.dataTransfer?.files?.length) return

    this.inputTarget.files = event.dataTransfer.files
    this.updateFileName()
  }

  fileSelected() {
    this.updateFileName()
  }

  updateFileName() {
    const file = this.inputTarget.files?.[0]
    if (this.hasFileNameTarget) {
      this.fileNameTarget.textContent = file ? file.name : "No file selected"
    }
  }
}