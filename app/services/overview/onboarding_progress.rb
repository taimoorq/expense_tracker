module Overview
  class OnboardingProgress
    VERSION = "financial-foundations-v1".freeze
    Result = Data.define(:version, :visible, :complete, :dismissed, :states, :completed_count)

    def self.call(user:, data:)
      new(user: user, data: data).call
    end

    def initialize(user:, data:)
      @user = user
      @data = data
    end

    def call
      provisioned = Identity::PersonalWorkspaceProvisioner.call(user: user)
      membership = provisioned.membership
      sync_version!(membership)
      states = derived_states
      complete = states.values.all? { |state| state == :done }
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

    attr_reader :data, :user

    def derived_states
      {
        accounts: accounts_state,
        recurring: recurring_state,
        month: month_state,
        review: review_state
      }
    end

    def accounts_state
      data.fetch(:accounts).any? ? :done : :next
    end

    def recurring_state
      total = data.fetch(:template_total)
      linked = data.fetch(:linked_template_total)
      return :done if total.positive? && linked == total
      return :in_progress if total.positive? || linked.positive?

      :next
    end

    def month_state
      return :next if data[:current_month].blank?
      return :done if data.fetch(:current_month_entries).any?

      :in_progress
    end

    def review_state
      return :next if data.fetch(:current_month_entries).empty?
      return :done if data.fetch(:review_attention_count).zero? || data.fetch(:linked_paid_entries_count).positive?

      :in_progress
    end

    def sync_version!(membership)
      return if membership.onboarding_version == VERSION

      membership.update!(
        onboarding_version: VERSION,
        onboarding_completed_at: nil,
        onboarding_dismissed_at: nil
      )
    end

    def persist_completion!(membership)
      return if membership.onboarding_completed_at.present?

      membership.update!(onboarding_completed_at: Time.current)
    end
  end
end
