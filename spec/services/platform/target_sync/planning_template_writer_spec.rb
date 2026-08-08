require "rails_helper"

RSpec.describe Platform::TargetSync::PlanningTemplateWriter do
  def prepare_target(user)
    result = Platform::TargetBackfill::Runner.call(user: user)
    expect(result).to be_success
    result.workspace.update!(target_writes_enabled: true)
    result.workspace
  end

  it "creates, edits, and archives one mapped target template without duplication" do
    user = create(:user)
    account = create(:account, user: user)
    workspace = prepare_target(user)

    source = Planning::LegacyTemplateWriter.create(
      scope: user.subscriptions,
      attributes: {
        name: "Music",
        amount: 12,
        due_day: 8,
        linked_account: account,
        active: true
      }
    )
    mapping = workspace.legacy_record_mappings.find_by!(
      legacy_record_type: "Subscription",
      legacy_record_id: source.id,
      target_record_type: "PlanningTemplate"
    )
    target = PlanningTemplate.find(mapping.target_record_id)

    expect(target).to have_attributes(name: "Music", default_amount: 12.to_d, source_account: account)
    expect(target.recurrence_rule).to have_attributes(cadence: "monthly", day_one: 8)

    expect(
      Planning::LegacyTemplateWriter.update(resource: source, attributes: { amount: 15, due_day: 10 })
    ).to be(true)
    expect(target.reload).to have_attributes(default_amount: 15.to_d)
    expect(target.recurrence_rule.reload.day_one).to eq(10)
    expect(workspace.planning_templates.count).to eq(1)

    expect(Planning::LegacyTemplateWriter.destroy(resource: source)).to be(true)
    expect(target.reload.archived_at).to be_present
    expect(mapping.reload).to be_status_omitted
  end

  it "rolls back a legacy card schedule that cannot create a valid target policy" do
    user = create(:user)
    liability = create(:account, user: user, kind: :credit_card)
    workspace = prepare_target(user)

    expect do
      @source = Planning::LegacyTemplateWriter.create(
        scope: user.credit_cards,
        attributes: {
          name: "Card",
          minimum_payment: 25,
          due_day: 18,
          priority: 1,
          linked_account: liability,
          active: true
        }
      )
    end.not_to change(CreditCard, :count)

    expect(@source.errors.full_messages).to include(
      "A credit card schedule requires both the card and payment accounts"
    )
    expect(workspace.planning_templates).to be_empty
  end
end
