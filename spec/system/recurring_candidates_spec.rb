require "rails_helper"

RSpec.describe "Reviewing recurring candidates", type: :system, js: true do
  include RecurringCandidateHelpers
  before { page.driver.browser.logs.get(:browser) }
  after do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    errors = page.driver.browser.logs.get(:browser).select { |entry| entry.level == "SEVERE" && entry.message.match?(/Uncaught|Error connecting controller|Content missing/) }
    expect(errors).to be_empty
  end

  it "builds recurring items one at a time, adds one month item, and restores an ignored candidate" do
    user = create(:user)
    account, = recurring_candidate(user: user)
    recurring_candidate(user: user, account: account, name: "Music subscription")
    month = create(:budget_month, user: user, month_on: Date.new(2026, 9, 1), label: "September 2026")
    sign_in_as user
    visit account_recurring_candidates_path(account)
    find("li", text: "Cloud storage").click_link("Review candidate")
    wait_for_review_navigation
    fill_in "Name", with: "My cloud storage"
    click_button "Save recurring transaction"
    expect(page).to have_content("Linked to My cloud storage")
    expect(user.expense_entries.count).to eq(0)
    click_link "Add to month"
    wait_for_review_navigation
    select "September 2026", from: "Budget month"
    click_button "Preview month"
    wait_for_review_navigation
    expect(page).to have_content("Status: Planned")
    click_button "Add planned item"
    expect(page).to have_content("Already in this month")
    expect(month.expense_entries.count).to eq(1)
    click_link "Review more candidates"
    wait_for_review_navigation
    expect(page).to have_content("Music subscription")
    find("li", text: "Music subscription").click_link("Review candidate")
    wait_for_review_navigation
    click_button "Ignore candidate"
    expect(page).to have_content("Candidate ignored")
    page.refresh
    click_button "Restore to review"
    expect(page).to have_button("Save recurring transaction")
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    expect(page).to have_no_css("turbo-frame[complete] .turbo-frame-error")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
    expect(page).to have_css(".ta-sidebar", visible: :all) { |element| element.evaluate_script("this.getBoundingClientRect().right") <= 1 }
    page.execute_script("document.getElementById('candidate_template_name').scrollIntoView({block: 'center', behavior: 'instant'})")
    duplicate_ids = page.evaluate_script("Array.from(document.querySelectorAll('#recurring_review [id]')).map(e => e.id).filter((id, i, ids) => ids.indexOf(id) !== i)")
    expect(duplicate_ids).to be_empty
    save_settled_screenshot("recurring-candidate-mobile.png")
  end

  it "reveals bill settings, preserves errors, and links an existing template through Turbo" do
    user = create(:user, last_seen_release_version: Platform::ReleaseCatalog.latest.version)
    account, candidate = recurring_candidate(user: user)
    bill = create(:monthly_bill, user: user, name: "Cloud storage", default_amount: 12, due_day: 8, linked_account: account)
    sign_in_as user
    visit account_recurring_candidate_path(account, candidate[:key])
    expect(page).to have_content("Possible existing recurring transactions")
    select "Monthly bill", from: "Recurring type"
    expect(page).to have_select("Frequency", visible: true)
    select "Quarterly", from: "Frequency"
    check "Jan"
    click_button "Save recurring transaction"
    expect(page).to have_content("must include 4 months")
    expect(page).to have_field("Name", with: "Cloud storage")
    expect(page).to have_css("[role='alert']:focus")
    select_option = find("#template_token option[value='monthly_bill:#{bill.id}']")
    select_option.select_option
    click_button "Link existing"
    expect(page).to have_content("Linked to Cloud storage")
    expect(user.monthly_bills.count).to eq(1)
    expect(user.subscriptions.count).to eq(0)
    save_settled_screenshot("recurring-candidate-linked-desktop.png")
  end

  it "keeps Ignore candidate under the pointer when a frame finishes loading" do
    user = create(:user)
    account, = recurring_candidate(user: user)
    create(:subscription, user: user, name: "Existing storage", amount: 12, linked_account: account)
    sign_in_as user
    visit account_recurring_candidates_path(account)

    # Hold the frame-load handler until the pointer is over the newly rendered button.
    # This makes the slow-render race reproducible without a timing-dependent sleep.
    page.execute_script(<<~JS)
      const frame = document.getElementById("recurring_review");
      frame.addEventListener("turbo:frame-load", event => {
        event.stopImmediatePropagation();
        frame.setAttribute("data-frame-load-held", "");
        window.releaseReviewFrameLoad = () => {
          delete window.releaseReviewFrameLoad;
          frame.removeAttribute("data-frame-load-held");
          frame.dispatchEvent(new Event("turbo:frame-load", { bubbles: true }));
        };
      }, { capture: true, once: true });
    JS
    click_link "Review candidate"
    expect(page).to have_css("#recurring_review[data-frame-load-held]")
    expect(page).to have_no_css("html[aria-busy='true']")
    find_button("Ignore candidate").hover
    page.execute_script("window.releaseReviewFrameLoad()")
    page.driver.browser.action.click.perform

    expect(page).to have_content("Candidate ignored")
    expect(account.recurring_candidate_decisions.reload.sole).to be_status_ignored
  ensure
    page.execute_script("window.releaseReviewFrameLoad?.()")
  end

  def wait_for_review_navigation
    # Frame HTML appears before Turbo finishes reading the response and updating history.
    # Starting the next navigation then can abort that response and leak a console error.
    page.evaluate_async_script(<<~JS)
      const done = arguments[0];
      document.getElementById("recurring_review").loaded.then(() => done());
    JS
    expect(page).to have_no_css("html[aria-busy='true']")
  end

  def save_settled_screenshot(filename)
    page.driver.browser.execute_async_script(<<~JS)
      const done = arguments[arguments.length - 1];
      const animations = document.getAnimations().filter(animation =>
        animation.effect.getComputedTiming().iterations !== Infinity
      );
      Promise.allSettled(animations.map(animation => animation.finished))
        .then(() => requestAnimationFrame(() => requestAnimationFrame(done)));
    JS
    page.save_screenshot(Rails.root.join("tmp/screenshots", filename))
  end
end
