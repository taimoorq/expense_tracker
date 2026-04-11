module Recurring
  class GenerateMonthRecurringEntries
    def initialize(budget_month:, templates:)
      @budget_month = budget_month
      @templates = templates
    end

    def call
      created = 0

      each_template do |template|
        template.recurring_month_occurrences(@budget_month.month_on).each do |occurred_on|
          next if template.generated_entry_exists?(@budget_month, occurred_on)

          @budget_month.expense_entries.create!(
            template.build_generated_entry_attributes(month_on: @budget_month.month_on, occurred_on: occurred_on)
          )
          created += 1
        end
      end

      created
    end

    private

    def each_template(&block)
      if @templates.respond_to?(:find_each)
        @templates.find_each(&block)
      else
        Array(@templates).each(&block)
      end
    end
  end
end
