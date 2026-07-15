require "rails_helper"

RSpec.describe "Responsive accessibility contracts", type: :system, js: true do
  VIEWPORT_WIDTHS = [ 320, 375, 768, 1024, 1440, 1800 ].freeze

  after do
    page.current_window.resize_to(1_400, 1_400)
  end

  it "keeps primary product screens within the viewport with one page heading" do
    user = create(:user, email: "responsive@example.com")
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))
    account = create(:account, user: user, name: "Checking", kind: :checking)
    create(:account_snapshot, account: account, recorded_on: Date.current, balance: 2_500)
    create(:expense_entry,
      user: user,
      budget_month: month,
      source_account: account,
      occurred_on: Date.current,
      section: :fixed,
      category: "Utilities",
      payee: "Power Company",
      planned_amount: 110,
      status: :planned)

    sign_in_as(user)

    paths = [
      root_path,
      budget_month_path(month),
      planning_templates_path,
      accounts_path,
      backup_restore_path,
      settings_path
    ]

    VIEWPORT_WIDTHS.each do |width|
      page.current_window.resize_to(width, 1_000)

      paths.each do |path|
        visit path
        page.execute_script("document.querySelector('.ta-toast-stack')?.remove()")

        expect(page).to have_css("main#main-content")
        expect(page.evaluate_script("document.querySelectorAll('h1').length")).to eq(1), "expected one h1 at #{path} and #{width}px"
        overflow = horizontal_overflow
        expect(overflow).to be <= 1, "expected no page overflow at #{path} and #{width}px (#{overflow}px; #{overflowing_elements.join(', ')})"
      end
    end
  end

  it "applies every theme and preserves touch-sized primary controls on mobile" do
    user = create(:user, email: "themes-responsive@example.com")
    sign_in_as(user)
    page.current_window.resize_to(375, 900)
    visit settings_path

    {
      "Earth" => "earth",
      "Indigo" => "indigo",
      "Emerald" => "emerald",
      "Sunset" => "sunset"
    }.each do |label, key|
      select label, from: "Color scheme"

      expect(page).to have_css("body.ta-theme-#{key}", wait: 5)
      expect(page).to have_select("Color scheme", selected: label)
      expect(horizontal_overflow).to be <= 1
    end

    undersized_controls = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll('.ta-action-btn, .ta-icon-btn'))
        .filter((element) => {
          const style = window.getComputedStyle(element)
          return style.display !== 'none' && style.visibility !== 'hidden' && element.getBoundingClientRect().height > 0
        })
        .filter((element) => element.getBoundingClientRect().height < 43.5)
        .map((element) => element.textContent.trim() || element.getAttribute('aria-label'))
    JS

    expect(undersized_controls).to eq([])
  end

  it "keeps breadcrumbs on their own content line and omits the current page label" do
    user = create(:user, email: "header-contract@example.com")
    month = create(:budget_month, user: user, month_on: Date.new(2026, 7, 1), label: "July 2026")

    sign_in_as(user)
    visit budget_month_path(month)

    expect(page).to have_no_css(".ta-topbar h1, .ta-topbar nav[aria-label='Breadcrumb']")
    expect(page).to have_css(".ta-content > .ta-content-header > .ta-breadcrumb-row nav[aria-label='Breadcrumb']")
    expect(page).to have_css(".ta-breadcrumb-row a", text: "Months", exact_text: true)
    expect(page).to have_no_css(".ta-breadcrumb-row", text: "July 2026")
    expect(page).to have_css(".ta-content-header .ta-page-header h1", text: "July 2026", exact_text: true)

    header_order = page.evaluate_script(<<~JS)
      (() => {
        const header = document.querySelector('.ta-content-header')
        return Array.from(header.children).map((element) => element.className)
      })()
    JS
    expect(header_order.first).to include("ta-breadcrumb-row")
    expect(header_order.second).to include("ta-page-header")

    visit budget_months_path

    expect(page).to have_no_css(".ta-breadcrumb-row")
    expect(page).to have_css(".ta-content-header h1", text: "Months", exact_text: true)
  end

  private

  def horizontal_overflow
    page.evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")
  end

  def overflowing_elements
    page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll('body *'))
        .filter((element) => {
          const rect = element.getBoundingClientRect()
          return rect.width > 0 && rect.right > document.documentElement.clientWidth + 1
        })
        .slice(0, 8)
        .map((element) => `${element.tagName.toLowerCase()}.${Array.from(element.classList).slice(0, 3).join('.')}`)
    JS
  end
end
