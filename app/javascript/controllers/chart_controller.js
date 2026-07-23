import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    type: String,
    title: String,
    labels: Array,
    data: Array,
    datasets: Array,
    options: Object
  }

  connect() {
    this.describeChart()
    this.beforeCacheHandler = () => this.destroyChart()
    document.addEventListener("turbo:before-cache", this.beforeCacheHandler)

    this.renderWhenReady()
  }

  disconnect() {
    this.destroyChart()

    if (this.beforeCacheHandler) {
      document.removeEventListener("turbo:before-cache", this.beforeCacheHandler)
    }
  }

  renderChart() {
    this.destroyChart()

    if (!(this.element instanceof HTMLCanvasElement)) return
    if (!window.Chart) return

    const chartType = this.typeValue || "bar"
    const labels = this.labelsValue || []
    const datasets = this.hasDatasetsValue && this.datasetsValue.length > 0 ? this.datasetsValue : [
      {
        label: this.titleValue || "Series",
        data: this.dataValue || [],
        backgroundColor: this.defaultColors(chartType),
        borderColor: this.themeColor("--ta-accent", "#4F46E5"),
        borderWidth: 2,
        tension: 0.3
      }
    ]

    const defaultOptions = {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: { position: "bottom" },
        title: {
          display: !!this.titleValue,
          text: this.titleValue
        }
      }
    }

    const customOptions = this.hasOptionsValue ? this.optionsValue : {}
    const chartOptions = {
      ...defaultOptions,
      ...customOptions,
      plugins: {
        ...defaultOptions.plugins,
        ...(customOptions.plugins || {})
      },
      scales: {
        ...(defaultOptions.scales || {}),
        ...(customOptions.scales || {})
      }
    }

    this.chart = new window.Chart(this.element.getContext("2d"), {
      type: chartType,
      data: { labels, datasets },
      options: chartOptions
    })
  }

  renderWhenReady() {
    if (window.Chart) {
      this.renderChart()
      return
    }

    this.chartWaitRetries = (this.chartWaitRetries || 0) + 1
    if (this.chartWaitRetries > 20) {
      this.element.setAttribute("data-chart-state", "unavailable")
      return
    }

    setTimeout(() => this.renderWhenReady(), 50)
  }

  destroyChart() {
    if (!this.chart) return

    this.chart.destroy()
    this.chart = null
  }

  defaultColors(type) {
    if (type === "doughnut" || type === "pie") {
      return [ "--ta-accent", "--ta-info", "--ta-success", "--ta-warning", "--ta-danger", "--ta-feature" ]
        .map((name) => this.colorWithAlpha(this.themeColor(name, "#4F46E5"), 0.8))
    }

    return this.colorWithAlpha(this.themeColor("--ta-accent", "#4F46E5"), 0.55)
  }

  themeColor(name, fallback) {
    return window.getComputedStyle(document.body).getPropertyValue(name).trim() || fallback
  }

  colorWithAlpha(color, alpha) {
    const normalized = color.trim()
    const shortHex = /^#([0-9a-f]{3})$/i.exec(normalized)
    const longHex = /^#([0-9a-f]{6})$/i.exec(normalized)
    const hex = longHex?.[1] || shortHex?.[1].split("").map((character) => character.repeat(2)).join("")

    if (!hex) return normalized

    const channels = [ 0, 2, 4 ].map((index) => Number.parseInt(hex.slice(index, index + 2), 16))
    return `rgba(${channels.join(", ")}, ${alpha})`
  }

  describeChart() {
    if (!(this.element instanceof HTMLCanvasElement)) return

    const title = this.titleValue || "Financial chart"
    const labels = this.labelsValue || []
    const range = labels.length > 0 ? ` Covers ${labels.length} ${labels.length === 1 ? "period" : "periods"}.` : ""
    const description = `${title}.${range} A text summary is provided next to this chart.`

    this.element.setAttribute("role", "img")
    this.element.setAttribute("aria-label", description)
    this.element.textContent = description
  }
}
