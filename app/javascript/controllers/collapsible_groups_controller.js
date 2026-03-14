import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["group"]
  static values = { storageKey: String }

  connect() {
    this.toggleListeners = new Map()
    this.persistenceSuspended = false
    this.defaultState = this.captureState()

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

  withPersistenceSuspended(callback) {
    const previous = this.persistenceSuspended
    this.persistenceSuspended = true

    try {
      callback()
    } finally {
      this.persistenceSuspended = previous
    }
  }

  restoreState() {
    const savedState = this.readState() || this.defaultState
    if (!savedState) return

    this.groupTargets.forEach((group) => {
      const groupId = group.dataset.groupId
      if (!groupId || !(groupId in savedState)) return

      group.open = savedState[groupId]
    })
  }

  saveState() {
    if (!this.hasStorageKeyValue || this.persistenceSuspended) return

    const state = this.captureState()

    try {
      window.localStorage.setItem(this.storageKeyValue, JSON.stringify(state))
    } catch (_error) {
      // Ignore storage failures so timeline interactions still work.
    }
  }

  captureState() {
    return this.groupTargets.reduce((result, group) => {
      const groupId = group.dataset.groupId
      if (!groupId) return result

      result[groupId] = group.open
      return result
    }, {})
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
