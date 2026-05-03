require "rails_helper"

RSpec.describe "Sidebar navigation", type: :system, js: true do
  it "opens settings as a full-page visit from a month detail page" do
    user = create(:user, email: "sidebar-settings@example.com")
    month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    create(:expense_entry, budget_month: month, user: user, payee: "Rent", planned_amount: 1200)

    sign_in_as(user)
    visit budget_month_path(month)

    click_link "Settings"

    expect(page).to have_current_path(settings_path)
    expect(page).to have_content("Appearance and app settings")
  end

  it "shows icon labels when hovering collapsed sidebar links" do
    user = create(:user, email: "sidebar-hover@example.com")

    sign_in_as(user)
    visit root_path

    unless page.evaluate_script("document.body.classList.contains('ta-shell-collapsed')")
      find("button[aria-label='Toggle navigation']", visible: true).click
    end

    months_link = find("a[aria-label='Months']")
    expect(months_link[:title]).to eq("")
    expect(page.evaluate_script("Number(getComputedStyle(document.querySelector(\"a[aria-label='Months'] .ta-sidebar-label\")).opacity)")).to eq(0)

    months_link.hover

    label_opacity = page.evaluate_async_script(<<~JS)
      const done = arguments[0]
      const label = document.querySelector("a[aria-label='Months'] .ta-sidebar-label")
      const startedAt = performance.now()

      function checkOpacity() {
        const opacity = Number(getComputedStyle(label).opacity)

        if (opacity > 0.9 || performance.now() - startedAt > 1000) {
          done(opacity)
          return
        }

        requestAnimationFrame(checkOpacity)
      }

      checkOpacity()
    JS

    label_extends_past_icon = page.evaluate_script(<<~JS)
      (() => {
        const link = document.querySelector("a[aria-label='Months']")
        const label = link.querySelector(".ta-sidebar-label")
        const linkRect = link.getBoundingClientRect()
        const labelRect = label.getBoundingClientRect()

        return labelRect.left > linkRect.right && labelRect.width > linkRect.width
      })()
    JS

    expect(label_opacity).to be > 0.9
    expect(label_extends_past_icon).to be(true)
  end
end
