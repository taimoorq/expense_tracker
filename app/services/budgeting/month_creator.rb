module Budgeting
  class MonthCreator
    Result = Data.define(:success?, :budget_month, :notice, :wizard_step)

    def self.call(user:, budget_month_params:, month_workflow:, source_budget_month:, include_applicable_templates:)
      new(
        user: user,
        budget_month_params: budget_month_params,
        month_workflow: month_workflow,
        source_budget_month: source_budget_month,
        include_applicable_templates: include_applicable_templates
      ).call
    end

    def initialize(user:, budget_month_params:, month_workflow:, source_budget_month:, include_applicable_templates:)
      @user = user
      @budget_month_params = budget_month_params
      @month_workflow = month_workflow
      @source_budget_month = source_budget_month
      @include_applicable_templates = include_applicable_templates
    end

    def call
      month_workflow == "clone" ? create_cloned_month : create_fresh_month
    end

    private

    attr_reader :user, :budget_month_params, :month_workflow, :source_budget_month, :include_applicable_templates

    def create_fresh_month
      budget_month = user.budget_months.new(budget_month_params)
      normalize_budget_month_label(budget_month)

      return Result.new(success?: false, budget_month: budget_month, notice: nil, wizard_step: 1) unless budget_month.save

      generation_summary = generate_applicable_templates_for(budget_month)
      Result.new(success?: true, budget_month: budget_month, notice: creation_notice("Budget month created.", generation_summary), wizard_step: nil)
    end

    def create_cloned_month
      unless source_budget_month
        budget_month = user.budget_months.new
        budget_month.errors.add(:base, "Choose a month to clone before continuing.")
        return Result.new(success?: false, budget_month: budget_month, notice: nil, wizard_step: 0)
      end

      budget_month = user.budget_months.new(clone_month_attributes(source_budget_month))
      normalize_budget_month_label(budget_month)
      return Result.new(success?: false, budget_month: budget_month, notice: nil, wizard_step: 0) unless budget_month.save

      cloned_entries = clone_source_entries(source_budget_month, budget_month)
      notice = "Budget month created and #{cloned_entries} entries cloned from #{source_budget_month.label}."
      Result.new(success?: true, budget_month: budget_month, notice: notice, wizard_step: nil)
    end

    def clone_month_attributes(source_month)
      target_month = source_month.month_on.next_month.beginning_of_month

      while user.budget_months.exists?(month_on: target_month)
        target_month = target_month.next_month.beginning_of_month
      end

      {
        month_on: target_month,
        label: target_month.strftime("%B %Y"),
        notes: source_month.notes
      }
    end

    def normalize_budget_month_label(budget_month)
      budget_month.label = budget_month.month_on.strftime("%B %Y") if budget_month.label.blank? && budget_month.month_on.present?
    end

    def generate_applicable_templates_for(budget_month)
      return { requested: false, total: 0 } unless include_applicable_templates

      total_created = 0
      total_created += Recurring::GenerateMonthPaychecks.new(budget_month: budget_month).call
      total_created += Recurring::GenerateMonthSubscriptions.new(budget_month: budget_month).call
      total_created += Recurring::GenerateMonthMonthlyBills.new(budget_month: budget_month).call
      total_created += Recurring::GenerateMonthPaymentPlans.new(budget_month: budget_month).call
      total_created += Recurring::EstimateMonthCreditCards.new(budget_month: budget_month).call

      { requested: true, total: total_created }
    end

    def creation_notice(base_message, generation_summary)
      return base_message unless generation_summary[:requested]
      return "#{base_message} No planning templates were imported." if generation_summary[:total].zero?

      "#{base_message} Imported #{generation_summary[:total]} planning template#{generation_summary[:total] == 1 ? '' : 's'} for this month."
    end

    def clone_source_entries(source_month, target_month)
      source_month.expense_entries.where.not(source_file: CreditCard.template_source_file).find_each.sum do |entry|
        target_month.expense_entries.create!(
          occurred_on: shifted_date(entry.occurred_on, target_month.month_on),
          section: entry.section,
          category: entry.category,
          payee: entry.payee,
          planned_amount: entry.actual_amount.presence || entry.planned_amount,
          actual_amount: nil,
          account: entry.account,
          status: :planned,
          need_or_want: entry.need_or_want,
          notes: entry.notes,
          source_file: entry.source_file,
          source_account_id: entry.source_account_id,
          source_template_type: entry.source_template_type,
          source_template_id: entry.source_template_id
        )
        1
      end
    end

    def shifted_date(date, target_month_on)
      return nil if date.blank?

      day = [ date.day, target_month_on.end_of_month.day ].min
      Date.new(target_month_on.year, target_month_on.month, day)
    end
  end
end
