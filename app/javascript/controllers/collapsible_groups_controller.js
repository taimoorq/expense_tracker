import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["group"]
  static values = { storageKey: String }

  connect() {
    this.toggleListeners = new Map()

    this.groupTargets.forEach((group) => {
      const listener = () => this.saveState()
      this.toggleListeners.set(group, listener)
      group.addEventListener("toggle", listener)
    })

    this.restoreState()
  }

  disconnect() {
    this.toggleListeners?.forEach((listener, group) => {
      group.removeEventListener("toggle", listener)
    })

    this.toggleListeners = null
  }

  expandAll() {
    this.groupTargets.forEach((group) => {
      group.open = true
    })

    this.saveState()
  }

  collapseAll() {
    this.groupTargets.forEach((group) => {
      group.open = false
    })

    this.saveState()
  }

  restoreState() {
    const savedState = this.readState()
    if (!savedState) return

    this.groupTargets.forEach((group) => {
      const groupId = group.dataset.groupId
      if (!groupId || !(groupId in savedState)) return

      group.open = savedState[groupId]
    })
  }

  saveState() {
    if (!this.hasStorageKeyValue) return

    const state = this.groupTargets.reduce((result, group) => {
      const groupId = group.dataset.groupId
      if (!groupId) return result

      result[groupId] = group.open
      return result
    }, {})

    try {
      window.localStorage.setItem(this.storageKeyValue, JSON.stringify(state))
    } catch (_error) {
      // Ignore storage failures so timeline interactions still work.
    }
  }

  readState() {
    if (!this.hasStorageKeyValue) return null

    try {
      const raw = window.localStorage.getItem(this.storageKeyValue)
      return raw ? JSON.parse(raw) : null
    } catch (_error) {
      return null
    }
  }
}
