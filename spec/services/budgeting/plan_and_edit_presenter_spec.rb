require "rails_helper"

RSpec.describe Budgeting::PlanAndEditPresenter do
  describe "#manual_entries_count" do
    it "counts manual-origin entries using the model provenance rule" do
      user = create(:user)
      budget_month = create(:budget_month, user: user)
      manual_entry = build_stubbed(:expense_entry, budget_month: budget_month, user: user, source_file: "manual")
      blank_legacy_entry = build_stubbed(:expense_entry, budget_month: budget_month, user: user, source_file: nil)
      recurring_entry = build_stubbed(:expense_entry, budget_month: budget_month, user: user, source_file: "pay_schedule")

      presenter = described_class.new(
        budget_month: budget_month,
        expense_entries: [ manual_entry, blank_legacy_entry, recurring_entry ]
      )

      expect(presenter.manual_entries_count).to eq(2)
    end
  end

  describe "#next_recommended_step" do
    it "starts with recurring items when no recurring action is complete" do
      user = create(:user)
      budget_month = create(:budget_month, user: user)

      presenter = described_class.new(budget_month: budget_month, expense_entries: [])

      expect(presenter.next_recommended_step).to eq(1)
      expect(presenter.next_recommended_label).to eq("add recurring")
    end

    it "moves to one-off items after at least one recurring action is complete" do
      user = create(:user)
      budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
      pay_schedule = create(:pay_schedule,
                            user: user,
                            name: "Employer",
                            first_pay_on: Date.new(2026, 3, 1),
                            day_of_month_one: 15,
                            amount: 2_500,
                            account: "Checking")
      recurring_entry = create(:expense_entry,
                               budget_month: budget_month,
                               user: user,
                               occurred_on: Date.new(2026, 3, 15),
                               section: :income,
                               category: "Paycheck",
                               payee: "Employer",
                               planned_amount: 2_500,
                               account: "Checking",
                               source_file: "pay_schedule",
                               source_template: pay_schedule)

      presenter = described_class.new(budget_month: budget_month, expense_entries: [ recurring_entry ])

      expect(presenter.next_recommended_step).to eq(2)
      expect(presenter.next_recommended_label).to eq("add one-off items")
    end

    it "moves to review cleanup once one-off items exist" do
      user = create(:user)
      budget_month = create(:budget_month, user: user)
      manual_entry = build_stubbed(:expense_entry, budget_month: budget_month, user: user, source_file: "manual")

      presenter = described_class.new(budget_month: budget_month, expense_entries: [ manual_entry ])

      expect(presenter.next_recommended_step).to eq(3)
      expect(presenter.next_recommended_label).to eq("review cleanup")
    end
  end

  describe "#auto_completed_count" do
    it "counts automatically paid recurring entries as review attention" do
      user = create(:user)
      budget_month = create(:budget_month, user: user)
      auto_completed_entry = build_stubbed(:expense_entry,
                                           budget_month: budget_month,
                                           user: user,
                                           status: :paid,
                                           actual_amount: 42,
                                           auto_completed_at: 1.hour.ago)
      confirmed_entry = build_stubbed(:expense_entry,
                                      budget_month: budget_month,
                                      user: user,
                                      status: :paid,
                                      actual_amount: 42,
                                      auto_completed_at: nil)

      presenter = described_class.new(
        budget_month: budget_month,
        expense_entries: [ auto_completed_entry, confirmed_entry ]
      )

      expect(presenter.auto_completed_count).to eq(1)
      expect(presenter.review_attention_count).to eq(1)
    end
  end

  describe "#recurring_actions" do
    it "summarizes generated and missing paychecks for the month" do
      user = create(:user)
      budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
      matched_schedule = create(:pay_schedule,
                                user: user,
                                name: "Main Employer",
                                first_pay_on: Date.new(2026, 3, 1),
                                day_of_month_one: 15,
                                amount: 2_500,
                                account: "Checking")
      create(:pay_schedule,
             user: user,
             name: "Side Client",
             first_pay_on: Date.new(2026, 3, 1),
             day_of_month_one: 20,
             amount: 800,
             account: "Checking")
      existing_entry = create(:expense_entry,
                              budget_month: budget_month,
                              user: user,
                              occurred_on: Date.new(2026, 3, 15),
                              section: :income,
                              category: "Paycheck",
                              payee: "Main Employer",
                              planned_amount: 2_500,
                              account: "Checking",
                              source_file: "pay_schedule",
                              source_template: matched_schedule)

      presenter = described_class.new(budget_month: budget_month, expense_entries: [ existing_entry ])
      paychecks = presenter.recurring_actions.find { |action| action.key == :pay_schedules }

      expect(paychecks.preview).to include(total: 2, matched: 1, remaining: 1, complete: false)
      expect(paychecks.status_summary).to eq("1 of 2 paycheck transactions already in this month")
      expect(paychecks.preview_items.first).to include(payee: "Side Client", occurred_on: Date.new(2026, 3, 20), planned_amount: 800)
    end

    it "counts moved recurring entries as already represented in the month" do
      user = create(:user)
      budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 6, 1), label: "June 2026")
      create(:pay_schedule,
             user: user,
             name: "Quria",
             first_pay_on: Date.new(2026, 6, 1),
             day_of_month_one: 30,
             amount: 2_600,
             account: "Checking")
      moved_entry = create(:expense_entry,
                           budget_month: budget_month,
                           user: user,
                           occurred_on: Date.new(2026, 6, 23),
                           section: :income,
                           category: "paycheck",
                           payee: "Quria",
                           planned_amount: 2_600,
                           actual_amount: 2_600,
                           account: "Checking",
                           status: :paid,
                           source_file: "manual")

      presenter = described_class.new(budget_month: budget_month, expense_entries: [ moved_entry ])
      paychecks = presenter.recurring_actions.find { |action| action.key == :pay_schedules }

      expect(paychecks.preview).to include(total: 1, matched: 1, remaining: 0, complete: true, alternate_count: 1)
      expect(paychecks).to be_alternate
      expect(paychecks.status_summary).to eq("1 of 1 paycheck transactions already in this month")
      expect(paychecks.alternate_items.first).to include(
        payee: "Quria",
        occurred_on: Date.new(2026, 6, 30),
        matched_on: Date.new(2026, 6, 23)
      )
    end

    it "keeps credit card estimates available to rerun after they are complete" do
      user = create(:user)
      budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
      card = create(:credit_card, user: user, name: "Rewards Card", minimum_payment: 45, due_day: 18, account: "Checking")
      card_entry = create(:expense_entry,
                          budget_month: budget_month,
                          user: user,
                          occurred_on: Date.new(2026, 3, 18),
                          section: :debt,
                          category: "Credit Card",
                          payee: "Rewards Card",
                          planned_amount: 45,
                          account: "Checking",
                          source_file: "credit_card_estimate",
                          source_template: card)

      presenter = described_class.new(budget_month: budget_month, expense_entries: [ card_entry ])
      card_action = presenter.recurring_actions.find { |action| action.key == :credit_cards }

      expect(card_action).to be_complete
      expect(card_action).to be_action_available
      expect(card_action.current_button_label).to eq("Re-estimate Card Payments")
    end
  end
end
