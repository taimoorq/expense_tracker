module Overview
  class OnboardingProgress
    VERSION = "financial-workflows-v2".freeze
    Result = Data.define(:version, :visible, :complete, :dismissed, :states, :completed_count)

    def self.call(user:, data:)
      new(user: user, data: data).call
    end

    def initialize(user:, data:)
      @user = user
      @data = data
    end

    def call
      provisioned = data[:workflow_status] || Identity::PersonalWorkspaceProvisioner.call(user: user)
      @membership = provisioned.membership
      sync_version!(membership)
      states = derived_states
      complete = membership.onboarding_completed_at.present? || states.values.all? { |state| state == :done }
      persist_completion!(membership) if complete

      Result.new(
        version: VERSION,
        visible: !complete && membership.onboarding_dismissed_at.blank?,
        complete: complete,
        dismissed: membership.onboarding_dismissed_at.present?,
        states: states,
        completed_count: states.values.count { |state| state == :done }
      )
    end

    private

    attr_reader :data, :user, :membership

    def derived_states
      {
        accounts: accounts_state,
        recurring: recurring_state,
        month: month_state,
        review: review_state
      }
    end

    def accounts_state
      return :next if data.fetch(:accounts).empty?
      return :done if membership.onboarding_balance_deferred_at.present?
      has_balance = if data.key?(:accounts_with_balance_sources_count)
        data[:accounts_with_balance_sources_count].positive?
      else
        user.account_snapshots.exists? || membership.budget_workspace.balance_observations.trusted.exists?
      end
      return :done if has_balance

      :in_progress
    end

    def recurring_state
      total = data.fetch(:template_total)
      return :done if total.positive? || membership.onboarding_recurring_skipped_at.present?

      :next
    end

    def month_state
      return :next if data[:current_month].blank?
      return :done if data.fetch(:current_month_entries).any? || recorded_activity?

      :in_progress
    end

    def review_state
      return :done if membership.onboarding_reviewed_at.present? || data.fetch(:linked_paid_entries_count).positive? || recorded_activity?
      return :next if data.fetch(:current_month_entries).empty?

      :in_progress
    end

    def sync_version!(membership)
      return if membership.onboarding_version == VERSION

      membership.update!(onboarding_version: VERSION)
    end

    def recorded_activity?
      return false unless data[:current_month]

      return @recorded_activity if defined?(@recorded_activity)
      @recorded_activity = membership.budget_workspace.financial_transactions.state_posted
        .where(effective_on: data[:current_month].month_on.all_month).exists?
    end

    def persist_completion!(membership)
      return if membership.onboarding_completed_at.present?

      membership.update!(onboarding_completed_at: Time.current)
    end
  end
end
