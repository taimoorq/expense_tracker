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
        borderColor: "rgb(79,70,229)",
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
    if (this.chartWaitRetries > 20) return

    setTimeout(() => this.renderWhenReady(), 50)
  }

  destroyChart() {
    if (!this.chart) return

    this.chart.destroy()
    this.chart = null
  }

  defaultColors(type) {
    if (type === "doughnut" || type === "pie") {
      return [
        "rgba(79, 70, 229, 0.8)",
        "rgba(14, 165, 233, 0.8)",
        "rgba(16, 185, 129, 0.8)",
        "rgba(245, 158, 11, 0.8)",
        "rgba(244, 63, 94, 0.8)",
        "rgba(168, 85, 247, 0.8)"
      ]
    }

    return "rgba(79, 70, 229, 0.55)"
  }
}
