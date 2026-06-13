require "rails_helper"

RSpec.describe Recurring::PlanningTemplateAccountLinking do
  it "relinks imported credit card payment and card accounts from backup names" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    visa_account = create(:account, user: user, name: "Visa Account", kind: :credit_card)
    card = create(:credit_card, user: user, name: "Rewards Visa", account: "Checking", payment_account: nil, linked_account: nil)

    described_class.relink_for(
      user,
      planning_template_data: {
        credit_cards: [
          {
            name: "Rewards Visa",
            payment_account: "Checking",
            linked_account: "Visa Account"
          }
        ]
      }
    )

    expect(card.reload.payment_account).to eq(checking)
    expect(card.linked_account).to eq(visa_account)
  end

  it "keeps the legacy account label fallback for credit card payment accounts" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    card = create(:credit_card, user: user, name: "Legacy Visa", account: "Checking", payment_account: nil)

    described_class.relink_for(user)

    expect(card.reload.payment_account).to eq(checking)
  end
end
