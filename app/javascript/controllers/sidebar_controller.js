import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["shell", "sidebar", "overlay", "toggleButton", "expandIcon", "collapseIcon", "mobileOpenIcon", "mobileCloseIcon"]

  connect() {
    const stored = localStorage.getItem("expense-tracker.sidebar.collapsed")
    this.desktopCollapsed = stored == null ? true : stored === "true"
    this.mobileOpen = false
    this.syncMode()
  }

  toggle() {
    if (this.isDesktop()) {
      this.applyDesktopState(!this.desktopCollapsed)
      return
    }

    this.applyMobileState(!this.mobileOpen)
  }

  close() {
    if (!this.isDesktop()) {
      this.applyMobileState(false)
    }
  }

  closeOnMobile() {
    this.close()
  }

  closeFromOutside(event) {
    if (this.isDesktop() || !this.mobileOpen) return
    if (!this.hasSidebarTarget) return

    const clickedToggle = this.hasToggleButtonTarget && this.toggleButtonTargets.some((button) => button.contains(event.target))
    const clickedInsideSidebar = this.sidebarTarget.contains(event.target)

    if (!clickedToggle && !clickedInsideSidebar) {
      this.applyMobileState(false)
    }
  }

  syncMode() {
    if (this.isDesktop()) {
      this.applyMobileState(false)
      this.applyDesktopState(this.desktopCollapsed)
      return
    }

    this.shellTarget.classList.remove("ta-shell-collapsed", "ta-shell-expanded")
    this.applyMobileState(this.mobileOpen)
    this.updateIcons()
  }

  applyDesktopState(collapsed) {
    this.desktopCollapsed = collapsed

    this.shellTarget.classList.toggle("ta-shell-collapsed", collapsed)
    this.shellTarget.classList.toggle("ta-shell-expanded", !collapsed)

    this.updateIcons()

    localStorage.setItem("expense-tracker.sidebar.collapsed", String(collapsed))
  }

  applyMobileState(open) {
    this.mobileOpen = open

    this.shellTarget.classList.toggle("ta-shell-mobile-nav-open", open)

    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.toggle("hidden", !open)
      this.overlayTarget.toggleAttribute("inert", !open)
    }

    this.updateIcons()
  }

  updateIcons() {
    const desktop = this.isDesktop()

    if (this.hasExpandIconTarget) {
      this.expandIconTargets.forEach((icon) => icon.classList.toggle("hidden", !desktop || !this.desktopCollapsed))
    }

    if (this.hasCollapseIconTarget) {
      this.collapseIconTargets.forEach((icon) => icon.classList.toggle("hidden", !desktop || this.desktopCollapsed))
    }

    if (this.hasMobileOpenIconTarget) {
      this.mobileOpenIconTargets.forEach((icon) => icon.classList.toggle("hidden", desktop || this.mobileOpen))
    }

    if (this.hasMobileCloseIconTarget) {
      this.mobileCloseIconTargets.forEach((icon) => icon.classList.toggle("hidden", desktop || !this.mobileOpen))
    }

    if (this.hasToggleButtonTarget) {
      this.toggleButtonTargets.forEach((button) => button.setAttribute("aria-expanded", String(desktop ? !this.desktopCollapsed : this.mobileOpen)))
    }
  }

  isDesktop() {
    return window.matchMedia("(min-width: 1024px)").matches
  }
}
