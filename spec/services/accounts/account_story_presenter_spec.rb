require "rails_helper"

RSpec.describe Accounts::AccountStoryPresenter do
  subject(:story) { described_class.new(account: account).call }

  let(:user) { create(:user) }

  {
    credit_card: [ :credit_card, "Charges", "Payments & credits" ],
    checking: [ :checking, "Money out", "Money in" ],
    savings: [ :savings, "Withdrawals", "Deposits" ],
    loan: [ :liability, "New debt", "Payments & credits" ],
    other_liability: [ :liability, "New debt", "Payments & credits" ],
    brokerage: [ :tracked_asset, "Withdrawals", "Contributions" ],
    retirement: [ :tracked_asset, "Withdrawals", "Contributions" ],
    other_asset: [ :tracked_asset, "Withdrawals", "Contributions" ],
    cash: [ :cash, "Cash out", "Cash in" ]
  }.each do |kind, (group, outgoing_label, incoming_label)|
    context "with a #{kind} account" do
      let(:account) { build(:account, user: user, kind: kind) }

      it "uses the #{group} story without calculating financial values" do
        expect(story).to include(
          story_group: group,
          outgoing_label: outgoing_label,
          incoming_label: incoming_label
        )
      end
    end
  end
end
