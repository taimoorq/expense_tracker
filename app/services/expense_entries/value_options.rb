module ExpenseEntries
  class ValueOptions
    def initialize(user:, budget_month:)
      @user = user
      @workspace = budget_month.budget_workspace || user.legacy_owned_budget_workspace
    end

    def categories
      @categories ||= unique_values([
        *(workspace&.categories&.active&.order(:display_order, :name)&.pluck(:name) || []),
        *entry_values(:category)
      ])
    end

    def payees
      @payees ||= unique_values([
        *entry_values(:payee),
        *recurring_names,
        *(workspace&.planning_templates&.active&.distinct&.pluck(:name) || []),
        *(workspace&.budget_items&.distinct&.pluck(:payee_snapshot) || []),
        *(workspace&.financial_transactions&.distinct&.pluck(:payee) || [])
      ])
    end

    def normalize(attributes)
      attributes.to_h.symbolize_keys.tap do |values|
        { category: :categories, payee: :payees }.each do |attribute, options|
          next unless values.key?(attribute) && values[attribute].present?

          value = values[attribute].to_s.strip
          values[attribute] = public_send(options).find { |existing| existing.casecmp?(value) } || value
        end
      end
    end

    private

    attr_reader :user, :workspace

    def entry_values(attribute)
      user.expense_entries.reorder(attribute).distinct.pluck(attribute)
    end

    def recurring_names
      Recurring::TemplateCatalog.models.flat_map do |model|
        scope = user.public_send(model.model_name.route_key)
        scope = scope.active_only if scope.respond_to?(:active_only)
        scope.reorder(:name).distinct.pluck(:name)
      end
    end

    def unique_values(values)
      values.filter_map { |value| value.to_s.strip.presence }
        .uniq(&:downcase)
        .sort_by(&:downcase)
    end
  end
end
