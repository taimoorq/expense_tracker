import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["chart", "loading", "error", "errorMessage"]
  static values = {
    title: String,
    loadingLabel: String,
    nodes: Array,
    links: Array,
    timeoutMs: { type: Number, default: 4000 }
  }

  connect() {
    this.beforeCacheHandler = () => this.destroyChart()
    this.resizeHandler = () => this.resizeOrRender()
    this.tabsSwitchedHandler = () => this.resizeOrRender()
    this.turboRenderHandler = () => this.resizeOrRender()
    this.loadingTimer = null

    document.addEventListener("turbo:before-cache", this.beforeCacheHandler)
    window.addEventListener("resize", this.resizeHandler)
    document.addEventListener("tabs:switched", this.tabsSwitchedHandler)
    document.addEventListener("turbo:render", this.turboRenderHandler)
    document.addEventListener("turbo:load", this.turboRenderHandler)

    this.showLoading()
    this.renderWhenReady()
  }

  disconnect() {
    this.destroyChart()
    this.clearLoadingTimer()

    if (this.beforeCacheHandler) {
      document.removeEventListener("turbo:before-cache", this.beforeCacheHandler)
    }

    if (this.resizeHandler) {
      window.removeEventListener("resize", this.resizeHandler)
    }

    if (this.tabsSwitchedHandler) {
      document.removeEventListener("tabs:switched", this.tabsSwitchedHandler)
    }

    if (this.turboRenderHandler) {
      document.removeEventListener("turbo:render", this.turboRenderHandler)
      document.removeEventListener("turbo:load", this.turboRenderHandler)
    }
  }

  renderWhenReady() {
    if (!this.isVisible()) {
      this.deferRender()
      return
    }

    if (window.echarts) {
      this.renderChartSafely()
      return
    }

    this.waitRetries = (this.waitRetries || 0) + 1
    if (this.waitRetries > 20) {
      this.showError(`The ${this.graphLabel()} took too long to load. Refresh the page and try again.`)
      return
    }

    if (!this.loadingTimer) {
      this.loadingTimer = setTimeout(() => {
        this.showLoading(`Still loading the ${this.graphLabel()}…`)
      }, this.timeoutMsValue)
    }

    setTimeout(() => this.renderWhenReady(), 50)
  }

  renderChartSafely() {
    try {
      this.renderChart()
      this.showChart()
    } catch (error) {
      this.showError(error?.message || "The graph could not be rendered.")
    }
  }

  renderChart() {
    this.destroyChart()
    if (!window.echarts) {
      throw new Error("ECharts is not available.")
    }

    this.chart = window.echarts.init(this.chartTarget)
    this.chart.setOption({
      animationDuration: 500,
      tooltip: {
        trigger: "item",
        triggerOn: "mousemove",
        formatter: (params) => {
          if (params.dataType === "edge") {
            return `${params.data.source} -> ${params.data.target}<br>$${Number(params.data.value).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
          }

          return params.data.name
        }
      },
      series: [
        {
          type: "sankey",
          left: 12,
          right: 12,
          top: 16,
          bottom: 16,
          emphasis: { focus: "adjacency" },
          nodeAlign: "justify",
          draggable: false,
          nodeWidth: 18,
          nodeGap: 16,
          lineStyle: {
            color: "gradient",
            curveness: 0.5,
            opacity: 0.35
          },
          label: {
            color: "#0f172a",
            fontSize: 12,
            fontWeight: 600
          },
          levels: [
            { depth: 0, itemStyle: { color: "#0ea5e9" }, lineStyle: { color: "source" } },
            { depth: 1, itemStyle: { color: "#16a34a" }, lineStyle: { color: "source" } },
            { depth: 2, itemStyle: { color: "#4f46e5" }, lineStyle: { color: "target" } }
          ],
          data: this.nodesValue || [],
          links: this.linksValue || []
        }
      ]
    })
  }

  destroyChart() {
    if (!this.chart) return

    this.chart.dispose()
    this.chart = null
  }

  resizeOrRender() {
    if (!this.isVisible()) return

    if (this.chart) {
      requestAnimationFrame(() => this.chart?.resize())
      return
    }

    this.showLoading()
    this.renderWhenReady()
  }

  showLoading(message = "Loading the monthly flow graph…") {
    this.clearLoadingTimer()
    this.loadingTarget.querySelector("[data-loading-text]")?.replaceChildren(document.createTextNode(message))
    this.loadingTarget.classList.remove("hidden")
    this.chartTarget.classList.add("hidden")
    this.errorTarget.classList.add("hidden")
  }

  showChart() {
    this.clearLoadingTimer()
    this.loadingTarget.classList.add("hidden")
    this.errorTarget.classList.add("hidden")
    this.chartTarget.classList.remove("hidden")
  }

  showError(message) {
    this.clearLoadingTimer()
    this.errorMessageTarget.textContent = message
    this.errorTarget.classList.remove("hidden")
    this.loadingTarget.classList.add("hidden")
    this.chartTarget.classList.add("hidden")
  }

  clearLoadingTimer() {
    if (!this.loadingTimer) return

    clearTimeout(this.loadingTimer)
    this.loadingTimer = null
  }

  isVisible() {
    return this.element.offsetParent !== null && this.element.getClientRects().length > 0
  }

  deferRender() {
    requestAnimationFrame(() => this.renderWhenReady())
  }

  graphLabel() {
    if (this.hasLoadingLabelValue && this.loadingLabelValue.length > 0) {
      return this.loadingLabelValue
    }

    if (this.hasTitleValue && this.titleValue.length > 0) {
      return this.titleValue
    }

    return "graph"
  }
}
