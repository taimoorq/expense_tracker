import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    title: String,
    nodes: Array,
    links: Array
  }

  connect() {
    this.beforeCacheHandler = () => this.destroyChart()
    this.resizeHandler = () => this.chart?.resize()

    document.addEventListener("turbo:before-cache", this.beforeCacheHandler)
    window.addEventListener("resize", this.resizeHandler)

    this.renderWhenReady()
  }

  disconnect() {
    this.destroyChart()

    if (this.beforeCacheHandler) {
      document.removeEventListener("turbo:before-cache", this.beforeCacheHandler)
    }

    if (this.resizeHandler) {
      window.removeEventListener("resize", this.resizeHandler)
    }
  }

  renderWhenReady() {
    if (window.echarts) {
      this.renderChart()
      return
    }

    this.waitRetries = (this.waitRetries || 0) + 1
    if (this.waitRetries > 20) return

    setTimeout(() => this.renderWhenReady(), 50)
  }

  renderChart() {
    this.destroyChart()
    if (!window.echarts) return

    this.chart = window.echarts.init(this.element)
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
}
