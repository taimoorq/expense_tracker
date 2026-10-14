import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "fallback", "panel", "list", "status"]
  static values = { label: String }

  connect() {
    this.values = Array.from(this.fallbackTarget.options, (option) => option.value)
    this.choices = []
    this.activeIndex = -1
    this.inputTarget.removeAttribute("list")
    this.inputTarget.setAttribute("role", "combobox")
    this.inputTarget.setAttribute("aria-autocomplete", "list")
    this.inputTarget.setAttribute("aria-controls", this.listTarget.id)
    this.close()
  }

  disconnect() {
    this.inputTarget.setAttribute("list", this.fallbackTarget.id)
  }

  search() {
    const query = this.normalized(this.inputTarget.value)
    const matches = this.values.filter((value) => this.normalized(value).includes(query))
    matches.sort((a, b) => Number(this.normalized(b).startsWith(query)) - Number(this.normalized(a).startsWith(query)))
    const similar = query.length >= 3 ? this.values.filter((value) => !matches.includes(value) && this.oneEditApart(query, this.normalized(value))) : []
    const existing = [...matches, ...similar]
    this.choices = existing.slice(0, 12).map((value) => ({ value, isNew: false }))
    const exactMatch = this.values.some((value) => this.normalized(value) === query)
    if (query && !exactMatch) this.choices.push({ value: this.inputTarget.value.trim(), isNew: true })
    this.activeIndex = -1

    if (existing.length > 12) {
      this.statusTarget.textContent = `Showing 12 of ${existing.length} ${this.labelValue} choices. Keep typing to narrow the list.`
    } else if (matches.length) {
      this.statusTarget.textContent = `Choose an existing ${this.labelValue}.`
    } else if (similar.length) {
      this.statusTarget.textContent = `Similar ${this.labelValue} values — check the spelling.`
    } else {
      this.statusTarget.textContent = `No existing ${this.labelValue} matches. You can use a new value.`
    }

    this.listTarget.replaceChildren(...this.choices.map((choice, index) => {
      const option = document.createElement("div")
      option.id = `${this.listTarget.id}_${index}`
      option.className = "ta-value-picker-option"
      option.setAttribute("role", "option")
      option.setAttribute("aria-selected", "false")
      option.dataset.index = index
      option.dataset.action = "pointerdown->value-picker#keepFocus click->value-picker#select mouseenter->value-picker#hover"
      option.textContent = choice.isNew ? `Use “${choice.value}” as a new ${this.labelValue}` : choice.value
      return option
    }))
    this.panelTarget.classList.remove("hidden")
    this.inputTarget.setAttribute("aria-expanded", "true")
    this.inputTarget.removeAttribute("aria-activedescendant")
  }

  keydown(event) {
    if (event.isComposing) return

    if (["ArrowDown", "ArrowUp"].includes(event.key)) {
      event.preventDefault()
      if (this.panelTarget.classList.contains("hidden")) this.search()
      if (!this.choices.length) return
      const step = event.key === "ArrowDown" ? 1 : -1
      this.activeIndex = this.activeIndex === -1 ? (step === 1 ? 0 : this.choices.length - 1) : (this.activeIndex + step + this.choices.length) % this.choices.length
      this.updateActiveState()
      this.listTarget.children[this.activeIndex]?.scrollIntoView({ block: "nearest" })
    } else if (event.key === "Enter" && !this.panelTarget.classList.contains("hidden") && this.activeIndex >= 0) {
      event.preventDefault()
      this.choose(this.activeIndex)
    } else if (event.key === "Escape" && !this.panelTarget.classList.contains("hidden")) {
      event.preventDefault()
      event.stopPropagation()
      this.close()
    } else if (event.key === "Tab") {
      this.close()
    }
  }

  keepFocus(event) {
    event.preventDefault()
  }

  select(event) {
    this.choose(Number(event.currentTarget.dataset.index))
  }

  hover(event) {
    this.activeIndex = Number(event.currentTarget.dataset.index)
    this.updateActiveState()
  }

  choose(index) {
    const choice = this.choices[index]
    if (!choice) return

    this.inputTarget.focus()
    this.inputTarget.value = choice.value
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
    this.close()
  }

  blur() {
    const exactMatch = this.values.find((value) => this.normalized(value) === this.normalized(this.inputTarget.value))
    if (exactMatch) this.inputTarget.value = exactMatch
    this.close()
  }

  close() {
    this.panelTarget.classList.add("hidden")
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
    this.activeIndex = -1
  }

  closeFromOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  updateActiveState() {
    Array.from(this.listTarget.children).forEach((option, index) => {
      option.setAttribute("aria-selected", String(index === this.activeIndex))
    })
    const active = this.listTarget.children[this.activeIndex]
    if (active) this.inputTarget.setAttribute("aria-activedescendant", active.id)
  }

  normalized(value) {
    return value.trim().toLowerCase()
  }

  oneEditApart(a, b) {
    if (Math.abs(a.length - b.length) > 1) return false
    if (a.length > b.length) return this.oneEditApart(b, a)

    let i = 0
    while (i < a.length && a[i] === b[i]) i += 1
    if (a.length !== b.length) return a.slice(i) === b.slice(i + 1)
    return a.slice(i + 1) === b.slice(i + 1) ||
      (a[i] === b[i + 1] && a[i + 1] === b[i] && a.slice(i + 2) === b.slice(i + 2))
  }
}
