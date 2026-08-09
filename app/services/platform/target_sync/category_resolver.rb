module Platform
  module TargetSync
    class CategoryResolver
      def self.call(workspace:, name:, flow_kind:, budget_group:)
        new(
          workspace: workspace,
          name: name,
          flow_kind: flow_kind,
          budget_group: budget_group
        ).call
      end

      def initialize(workspace:, name:, flow_kind:, budget_group:)
        @workspace = workspace
        @name = name.to_s.strip
        @flow_kind = flow_kind
        @budget_group = budget_group
      end

      def call
        return if name.blank?

        workspace.categories.active.find_by("lower(name) = ?", name.downcase) || create_category
      rescue ActiveRecord::RecordNotUnique
        retry
      end

      private

      attr_reader :budget_group, :flow_kind, :name, :workspace

      def create_category
        workspace.categories.create!(
          name: name,
          flow_kind: flow_kind,
          budget_group: budget_group,
          display_order: workspace.categories.maximum(:display_order).to_i + 1
        )
      end
    end
  end
end
