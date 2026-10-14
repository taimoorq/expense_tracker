require "rails_helper"

RSpec.describe "Entry payee and category choices", type: :system, js: true do
  let(:user) { create(:user) }
  let(:budget_month) { create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026") }

  after { page.current_window.resize_to(1_400, 1_400) }

  it "selects existing values despite a typo by keyboard and pointer in the Turbo composer" do
    earlier_month = create(:budget_month, user: user, month_on: Date.new(2026, 2, 1))
    create(:expense_entry, budget_month: earlier_month, payee: "Pepco", category: "Utilities")
    sign_in_as(user)
    visit budget_month_tab_path(budget_month, "entries")
    within("turbo-frame#entry_form") { click_link "Add entry" }

    within("turbo-frame#entry_wizard_modal") do
      expect(page).to have_css('input[role="combobox"]', count: 2)
      fill_in "Payee", with: "Pepxo"
      expect(page).to have_content("Similar payee values")
      find_field("Payee").send_keys(:arrow_down)
      expect(find_field("Payee")["aria-activedescendant"]).to be_present
      find_field("Payee").send_keys(:enter)
      expect(page).to have_field("Payee", with: "Pepco")
      expect(page).to have_button("Add to March 2026")

      fill_in "Category", with: "Utilites"
      find('[role="option"]', text: "Utilities", exact_text: true).click
      expect(page).to have_field("Category", with: "Utilities")
      find_field("Category").click
      expect(find_field("Category")["aria-expanded"]).to eq("true")
      find_field("Category").send_keys(:escape)
      expect(page).to have_css('input[aria-expanded="false"]', count: 2)
      fill_in "Amount", with: "89.33"
      click_button "Add to March 2026"
    end

    expect(page).to have_content("Entry added.")
    expect(budget_month.expense_entries.last.attributes.slice("category", "payee")).to eq("category" => "Utilities", "payee" => "Pepco")
  end

  it "accepts new values with no match and offers them on the next visit" do
    sign_in_as(user)
    visit new_wizard_budget_month_expense_entries_path(budget_month)
    expect(page).to have_css('input[role="combobox"]', count: 2)

    fill_in "Payee", with: "Neighborhood Garden"
    find('[role="option"]', text: "Use “Neighborhood Garden” as a new payee", exact_text: true).click
    fill_in "Category", with: "Gardening"
    expect(page).to have_css('[role="option"]', exact_text: "Use “Gardening” as a new category")
    fill_in "Amount", with: "25"
    click_button "Add to March 2026"

    expect(page).to have_content("Entry added.")
    expect(budget_month.expense_entries.last.attributes.slice("category", "payee")).to eq("category" => "Gardening", "payee" => "Neighborhood Garden")

    visit new_wizard_budget_month_expense_entries_path(budget_month)
    fill_in "Payee", with: "garden"
    expect(page).to have_css('[role="option"]', exact_text: "Neighborhood Garden")
    fill_in "Category", with: "gard"
    expect(page).to have_css('[role="option"]', exact_text: "Gardening")
  end

  it "keeps the shared editor picker usable on a narrow screen" do
    entry = create(:expense_entry, budget_month: budget_month, payee: "Water", category: "Utilities")
    create(:expense_entry, budget_month: budget_month, payee: "Neighborhood Garden", category: "Gardening")
    sign_in_as(user)
    page.current_window.resize_to(390, 844)
    visit budget_month_path(budget_month)
    find("a[aria-label='Edit entry'][href^='#{edit_budget_month_expense_entry_path(budget_month, entry)}']", match: :first).click

    within("turbo-frame#entry_editor_modal") do
      expect(page).to have_css('input[role="combobox"]', count: 2)
      fill_in "Payee", with: "garden"
      expect(page).to have_css('[role="option"]', exact_text: "Neighborhood Garden")
      expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
      find('[role="option"]', text: "Neighborhood Garden", exact_text: true).click
      fill_in "Category", with: "garden"
      find('[role="option"]', text: "Gardening", exact_text: true).click
      click_button "Update Entry"
    end

    expect(page).to have_content("Entry updated.")
    expect(entry.reload.attributes.slice("category", "payee")).to eq("category" => "Gardening", "payee" => "Neighborhood Garden")
  end
end
