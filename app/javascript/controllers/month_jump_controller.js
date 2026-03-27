import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["input", "panel", "results", "emptyState", "submitButton"]
  static values = { months: Array }

  connect() {
    this.activeIndex = -1
    this.filteredMonths = []
  }

  open() {
    this.search()
  }

  activate(event) {
    if (this.hasSubmitButtonTarget && (event.target === this.submitButtonTarget || this.submitButtonTarget.contains(event.target))) return
    if (this.inputTarget.disabled) return

    this.inputTarget.focus()
    this.open()
  }

  search() {
    const query = this.normalizedQuery()
    this.filteredMonths = query.length === 0 ? this.monthsValue.slice(0, 8) : this.monthsValue.filter((month) => month.search_text.includes(query)).slice(0, 8)
    this.activeIndex = this.filteredMonths.length > 0 ? 0 : -1
    this.render()
  }

  submit(event) {
    event.preventDefault()

    if (this.activeIndex >= 0 && this.filteredMonths[this.activeIndex]) {
      this.visit(this.filteredMonths[this.activeIndex].url)
      return
    }

    const exactMatch = this.monthsValue.find((month) => month.label.toLowerCase() === this.normalizedQuery())
    if (exactMatch) this.visit(exactMatch.url)
  }

  keydown(event) {
    if (this.panelTarget.classList.contains("hidden") && ["ArrowDown", "ArrowUp"].includes(event.key)) {
      this.open()
      event.preventDefault()
      return
    }

    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.moveActiveIndex(1)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.moveActiveIndex(-1)
    } else if (event.key === "Enter" && this.activeIndex >= 0 && this.filteredMonths[this.activeIndex]) {
      event.preventDefault()
      this.visit(this.filteredMonths[this.activeIndex].url)
    } else if (event.key === "Escape") {
      this.close()
    }
  }

  select(event) {
    const index = Number(event.currentTarget.dataset.index)
    const month = this.filteredMonths[index]
    if (!month) return

    this.visit(month.url)
  }

  hover(event) {
    this.activeIndex = Number(event.currentTarget.dataset.index)
    this.updateActiveState()
  }

  close() {
    this.panelTarget.classList.add("hidden")
  }

  closeFromOutside(event) {
    if (this.element.contains(event.target)) return

    this.close()
  }

  moveActiveIndex(step) {
    if (this.filteredMonths.length === 0) return

    this.activeIndex = (this.activeIndex + step + this.filteredMonths.length) % this.filteredMonths.length
    this.updateActiveState()
    this.scrollActiveIntoView()
  }

  render() {
    const hasResults = this.filteredMonths.length > 0
    this.resultsTarget.innerHTML = hasResults ? this.filteredMonths.map((month, index) => this.resultMarkup(month, index)).join("") : ""
    this.emptyStateTarget.classList.toggle("hidden", hasResults)
    this.panelTarget.classList.toggle("hidden", !hasResults && this.normalizedQuery().length === 0)

    if (hasResults || this.normalizedQuery().length > 0) {
      this.panelTarget.classList.remove("hidden")
    }

    this.updateActiveState()
  }

  updateActiveState() {
    this.resultsTarget.querySelectorAll("[data-month-jump-option]").forEach((option, index) => {
      const active = index === this.activeIndex
      option.classList.toggle("bg-indigo-50", active)
      option.classList.toggle("text-indigo-700", active)
      option.classList.toggle("border-indigo-100", active)
      option.setAttribute("aria-selected", active ? "true" : "false")
    })
  }

  scrollActiveIntoView() {
    const activeOption = this.resultsTarget.querySelector(`[data-index="${this.activeIndex}"]`)
    activeOption?.scrollIntoView({ block: "nearest" })
  }

  visit(url) {
    this.close()
    Turbo.visit(url)
  }

  normalizedQuery() {
    return this.inputTarget.value.trim().toLowerCase()
  }

  resultMarkup(month, index) {
    return `
      <button
        type="button"
        class="flex w-full items-center justify-between gap-3 border border-transparent px-4 py-3 text-left transition hover:bg-indigo-50 hover:text-indigo-700"
        data-index="${index}"
        data-month-jump-option
        data-action="mouseenter->month-jump#hover click->month-jump#select"
        aria-selected="false"
      >
        <span class="min-w-0">
          <span class="block truncate text-sm font-semibold text-current">${this.escapeHtml(month.label)}</span>
          <span class="block truncate text-xs text-slate-500">${this.escapeHtml(month.subtitle)}</span>
        </span>
        <span class="rounded-full bg-slate-100 px-2.5 py-1 text-[11px] font-semibold uppercase tracking-[0.16em] text-slate-500">
          Open
        </span>
      </button>
    `
  }

  escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll("\"", "&quot;")
      .replaceAll("'", "&#39;")
  }
}
