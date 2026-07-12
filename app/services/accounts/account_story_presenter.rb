module Accounts
  class AccountStoryPresenter
    STORY_GROUPS = {
      "checking" => :checking,
      "savings" => :savings,
      "credit_card" => :credit_card,
      "loan" => :liability,
      "other_liability" => :liability,
      "brokerage" => :tracked_asset,
      "retirement" => :tracked_asset,
      "other_asset" => :tracked_asset,
      "cash" => :cash
    }.freeze

    STORIES = {
      credit_card: {
        question: "Am I adding debt faster than I am paying it down?",
        chart_title: "Charges and payments over time",
        incoming_label: "Payments & credits",
        outgoing_label: "Charges",
        net_label: "Net debt movement",
        balance_label: "Ending debt",
        empty_message: "Import card activity or link paid entries to compare charges with payments and credits."
      },
      checking: {
        question: "How much money came in and where did it go?",
        chart_title: "Money in and money out over time",
        incoming_label: "Money in",
        outgoing_label: "Money out",
        net_label: "Net cash movement",
        balance_label: "Ending balance",
        empty_message: "Import bank activity or link paid entries to compare money in with money out."
      },
      savings: {
        question: "Is this balance growing, and how often am I drawing from it?",
        chart_title: "Deposits and withdrawals over time",
        incoming_label: "Deposits",
        outgoing_label: "Withdrawals",
        net_label: "Net contributions",
        balance_label: "Ending balance",
        empty_message: "Import savings activity or link paid entries to compare deposits with withdrawals."
      },
      liability: {
        question: "Is this debt falling, and how much am I paying?",
        chart_title: "Payments and new debt over time",
        incoming_label: "Payments & credits",
        outgoing_label: "New debt",
        net_label: "Net debt movement",
        balance_label: "Ending debt",
        empty_message: "Import liability activity or link paid entries to review debt movement."
      },
      tracked_asset: {
        question: "How is this account's tracked value changing?",
        chart_title: "Contributions and withdrawals over time",
        incoming_label: "Contributions",
        outgoing_label: "Withdrawals",
        net_label: "Net contributions",
        balance_label: "Tracked value",
        empty_message: "Add a balance source or activity to start reviewing changes in tracked value."
      },
      cash: {
        question: "Is this manually tracked balance still credible?",
        chart_title: "Cash in and cash out over time",
        incoming_label: "Cash in",
        outgoing_label: "Cash out",
        net_label: "Net cash movement",
        balance_label: "Ending balance",
        empty_message: "Record a snapshot and link paid entries to review cash movement."
      }
    }.freeze

    attr_reader :account

    def initialize(account:)
      @account = account
    end

    def call
      story.merge(
        story_group: story_group,
        liability: account.liability?,
        chart_type: "bar",
        incoming_color: "rgba(16, 185, 129, 0.72)",
        outgoing_color: "rgba(244, 63, 94, 0.72)"
      )
    end

    private

    def story_group
      STORY_GROUPS.fetch(account.kind)
    end

    def story
      STORIES.fetch(story_group)
    end
  end
end
