require "rails_helper"

RSpec.describe "Operation status", type: :system, js: true do
  it "refreshes durable progress and leaves the status frame for Home" do
    user = create(:user, email: "operation-status@example.com")
    provisioned = Identity::PersonalWorkspaceProvisioner.call(user: user)
    operation = create(
      :operation_run,
      budget_workspace: provisioned.workspace,
      actor_membership: provisioned.membership,
      operation_type: "commit_legacy_account_activity_import",
      state: "running",
      progress_current: 1,
      progress_total: 3,
      progress_label: "Preview validated",
      started_at: Time.current,
      retryable: true
    )

    sign_in_as(user)
    visit operation_run_path(operation)

    expect(page).to have_css("turbo-frame#operation_status_#{operation.id}", text: "Preview validated")

    operation.record_progress!(current: 2, total: 3, label: "Activity rows committed")

    expect(page).to have_css(
      "turbo-frame#operation_status_#{operation.id}",
      text: "Activity rows committed",
      wait: 5
    )

    operation.update!(
      state: "succeeded",
      completed_at: Time.current,
      progress_current: 3,
      progress_total: 3,
      progress_label: "Import complete"
    )

    expect(page).to have_css("turbo-frame#operation_status_#{operation.id}", text: "Complete", wait: 5)
    expect(page).to have_css('[data-controller~="operation-poll"][data-operation-poll-active-value="false"]')

    within("turbo-frame#operation_status_#{operation.id}") { click_link "Back to Home" }

    expect(page).to have_current_path(root_path)
    expect(page).to have_no_content("Content missing")
  end
end
