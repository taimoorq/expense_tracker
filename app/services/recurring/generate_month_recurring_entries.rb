module Recurring
  class GenerateMonthRecurringEntries
    def initialize(budget_month:, templates:)
      @budget_month = budget_month
      @templates = templates
    end

    def call
      @budget_month.with_lock do
        created = 0

        each_template do |template|
          template.recurring_month_occurrences(@budget_month.month_on).each do |occurred_on|
            next if template.generated_entry_exists?(@budget_month, occurred_on)

            attributes = template.build_generated_entry_attributes(month_on: @budget_month.month_on, occurred_on: occurred_on)
            created += 1 if create_generated_entry(attributes)
          end
        end

        created
      end
    end

    private

    def each_template(&block)
      if @templates.respond_to?(:find_each)
        @templates.find_each(&block)
      else
        Array(@templates).each(&block)
      end
    end

    def create_generated_entry(attributes)
      generated_key = attributes[:generated_entry_key]
      return @budget_month.expense_entries.create!(attributes).previously_new_record? if generated_key.blank?

      entry = @budget_month.expense_entries.create_or_find_by!(generated_entry_key: generated_key) do |generated_entry|
        generated_entry.assign_attributes(attributes.except(:generated_entry_key))
      end
      entry.previously_new_record?
    end
  end
end
