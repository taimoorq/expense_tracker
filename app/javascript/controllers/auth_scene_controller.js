import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["layer"]

  move(event) {
    const { innerWidth, innerHeight } = window
    const offsetX = event.clientX / innerWidth - 0.5
    const offsetY = event.clientY / innerHeight - 0.5

    this.layerTargets.forEach((element) => {
      const depth = Number(element.dataset.depth || 10)
      const x = offsetX * depth
      const y = offsetY * depth

      element.style.transform = `translate3d(${x}px, ${y}px, 0)`
    })
  }
}