import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  scroll(event) {
    const id = this.anchorId(event.currentTarget.getAttribute("href"))
    if (!id) return

    const target = document.getElementById(id)
    if (!target) return

    event.preventDefault()
    target.scrollIntoView({ block: "start", behavior: "auto" })
    this.focusTarget(target)
    this.pushHash(id)
  }

  anchorId(href) {
    if (!href) return null

    try {
      return new URL(href, window.location.href).hash.replace(/^#/, "") || null
    } catch (_error) {
      return href.replace(/^#/, "") || null
    }
  }

  focusTarget(target) {
    if (!target.hasAttribute("tabindex")) {
      target.setAttribute("tabindex", "-1")
    }

    target.focus({ preventScroll: true })
  }

  pushHash(id) {
    const url = new URL(window.location.href)
    if (url.hash === `#${id}`) return

    url.hash = id
    window.history.pushState(window.history.state, "", url)
  }
}
