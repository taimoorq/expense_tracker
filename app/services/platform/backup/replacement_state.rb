module Platform
  module Backup
    class ReplacementState
      FINANCIAL_SCOPES = Platform::Backup::V2::Preview::FINANCIAL_SCOPES.freeze

      def self.any?(user:, scopes:)
        new(user: user, scopes: scopes).any?
      end

      def initialize(user:, scopes:)
        @user = user
        @scopes = Array(scopes).map(&:to_s)
      end

      def any?
        return true if scopes.include?("planning_templates") && planning_templates?
        return true if scopes.include?("budget_months") && user.budget_months.exists?
        return true if scopes.include?("accounts") && user.accounts.exists?
        return true if scopes.include?("account_activity") && user.account_activity_imports.exists?

        target_financial_data?
      end

      private

      attr_reader :scopes, :user

      def planning_templates?
        [ user.pay_schedules, user.subscriptions, user.monthly_bills, user.payment_plans, user.credit_cards ].any?(&:exists?)
      end

      def target_financial_data?
        return false if (scopes & FINANCIAL_SCOPES).empty?

        workspace = user.legacy_owned_budget_workspace
        return false if workspace.blank?

        [
          workspace.accounts,
          workspace.budget_periods,
          workspace.planning_templates,
          workspace.financial_transactions,
          workspace.import_batches,
          workspace.balance_observations
        ].any?(&:exists?)
      end
    end
  end
end
