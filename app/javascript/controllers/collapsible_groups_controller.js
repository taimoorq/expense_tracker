import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["group"]

  expandAll() {
    this.groupTargets.forEach((group) => {
      group.open = true
    })
  }

  collapseAll() {
    this.groupTargets.forEach((group) => {
      group.open = false
    })
  }
}
