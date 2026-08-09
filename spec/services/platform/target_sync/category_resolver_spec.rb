require "rails_helper"

RSpec.describe Platform::TargetSync::CategoryResolver do
  it "reuses an active category case-insensitively" do
    workspace = create(:budget_workspace)
    existing = create(:category, budget_workspace: workspace, name: "Groceries")

    resolved = described_class.call(
      workspace: workspace,
      name: " groceries ",
      flow_kind: "outflow",
      budget_group: "variable"
    )

    expect(resolved).to eq(existing)
    expect(workspace.categories.count).to eq(1)
  end

  it "does not revive an archived category" do
    workspace = create(:budget_workspace)
    archived = create(:category, budget_workspace: workspace, name: "Travel", archived_at: Time.current)

    resolved = described_class.call(
      workspace: workspace,
      name: "Travel",
      flow_kind: "outflow",
      budget_group: "variable"
    )

    expect(resolved).not_to eq(archived)
    expect(resolved).to be_persisted
    expect(resolved).to have_attributes(name: "Travel", archived_at: nil)
  end
end
