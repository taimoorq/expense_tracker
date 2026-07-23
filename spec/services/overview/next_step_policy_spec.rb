require "rails_helper"

RSpec.describe Overview::NextStepPolicy do
  let(:month) { Struct.new(:label, :to_param).new("July 2026", "july-2026") }
  let(:base_context) do
    {
      accounts: [ Object.new ],
      template_total: 1,
      linked_template_total: 1,
      current_month: month,
      current_month_entries: [ Object.new ],
      review_attention_count: 0,
      manual_entries_count: 1
    }
  end

  it "opens the budget by default when a month needs review" do
    action = described_class.new(context: base_context.merge(review_attention_count: 2)).call

    expect(action).to include(
      primary_label: "Open Budget",
      primary_path: "/budget_months/july-2026/timeline",
      secondary_label: "Open Plan and Edit"
    )
    expect(action[:secondary_path]).to include("/budget_months/july-2026/entries")
    expect(action[:secondary_path]).to include("review=all")
    expect(action[:secondary_path]).to end_with("#plan-review")
  end

  it "opens the budget by default when a month has no entries" do
    action = described_class.new(context: base_context.merge(current_month_entries: [])).call

    expect(action).to include(
      primary_label: "Open Budget",
      primary_path: "/budget_months/july-2026/timeline",
      secondary_label: "Open Plan and Edit",
      secondary_path: "/budget_months/july-2026/entries"
    )
  end
end
