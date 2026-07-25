require "rails_helper"

RSpec.describe Budgeting::MonthFormState do
  def count_select_queries
    count = 0
    callback = lambda do |_name, _started, _finished, _unique_id, payload|
      count += 1 if payload[:sql].to_s.match?(/\ASELECT/i) && payload[:name] != "SCHEMA"
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    count
  end

  describe ".call" do
    it "defaults to a fresh workflow and enables template import when no source month is selected" do
      user = create(:user)
      march = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
      create(:expense_entry, budget_month: march, user: user)

      result = described_class.call(user: user, params: {})

      expect(result.month_workflow).to eq("fresh")
      expect(result.wizard_step).to eq(0)
      expect(result.include_applicable_templates).to be(true)
      expect(result.clone_preview).to be_nil
      expect(result.new_month_defaults).to eq({})
      expect(result.cloneable_month_options).to contain_exactly(
        hash_including(
          id: march.id,
          source_label: "March 2026",
          target_label: "April 2026",
          entry_count: 1
        )
      )
    end

    it "preselects clone workflow and next available month defaults when a source month is provided" do
      user = create(:user)
      source_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026", notes: "Carry over")
      create(:budget_month, user: user, month_on: Date.new(2026, 4, 1), label: "April 2026")

      result = described_class.call(
        user: user,
        params: ActionController::Parameters.new(source_month_id: source_month.id)
      )

      expect(result.month_workflow).to eq("clone")
      expect(result.include_applicable_templates).to be(false)
      expect(result.source_budget_month).to eq(source_month)
      expect(result.clone_preview).to include(id: source_month.id, target_label: "May 2026")
      expect(result.new_month_defaults).to eq(
        month_on: Date.new(2026, 5, 1),
        label: "May 2026"
      )
    end

    it "uses aggregate counts without loading historical entry records" do
      user = create(:user)
      months = 6.times.map do |index|
        create(:budget_month, user: user, month_on: Date.new(2026, index + 1, 1))
      end
      months.each_with_index do |month, index|
        create_list(:expense_entry, index + 1, user: user, budget_month: month)
      end

      result = nil
      queries = count_select_queries do
        result = described_class.call(user: user.reload, params: {})
      end

      expect(result.cloneable_month_options.map { |option| option[:entry_count] }).to eq([ 6, 5, 4, 3, 2, 1 ])
      expect(queries).to be <= 4
      expect(result.cloneable_budget_months).to all(satisfy { |month| !month.association(:expense_entries).loaded? })
    end
  end
end
