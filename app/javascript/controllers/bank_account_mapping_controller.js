import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["account", "newAccount"]

  connect() {
    this.sync()
  }

  sync() {
    const creatingAccount = this.accountTarget.value === ""
    this.newAccountTargets.forEach((field) => field.classList.toggle("hidden", !creatingAccount))
  }
}
