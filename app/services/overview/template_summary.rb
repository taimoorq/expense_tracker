module Overview
  class TemplateSummary
    TEMPLATE_TYPES = %i[pay_schedules subscriptions monthly_bills payment_plans credit_cards].freeze

    def initialize(user:, current_month:, current_month_entries:)
      @user = user
      @current_month = current_month
      @current_month_entries = current_month_entries
    end

    def call
      counts = {
        pay_schedules: user.pay_schedules.count,
        subscriptions: user.subscriptions.count,
        monthly_bills: user.monthly_bills.count,
        payment_plans: user.payment_plans.count,
        credit_cards: user.credit_cards.count
      }

      linked_counts = {
        pay_schedules: user.pay_schedules.where.not(linked_account_id: nil).count,
        subscriptions: user.subscriptions.where.not(linked_account_id: nil).count,
        monthly_bills: user.monthly_bills.where.not(linked_account_id: nil).count,
        payment_plans: user.payment_plans.where.not(linked_account_id: nil).count,
        credit_cards: user.credit_cards.where.not(linked_account_id: nil).count
      }

      {
        template_counts: counts,
        template_total: counts.values.sum,
        linked_template_counts: linked_counts,
        linked_template_total: linked_counts.values.sum,
        template_actions_completed: template_actions_completed
      }
    end

    private

    attr_reader :current_month, :current_month_entries, :user

    def template_actions_completed
      return 0 unless current_month

      [
        template_coverage_for_type(:pay_schedules).fetch(:complete),
        template_coverage_for_type(:subscriptions).fetch(:complete),
        template_coverage_for_type(:monthly_bills).fetch(:complete),
        template_coverage_for_type(:payment_plans).fetch(:complete),
        matching_template_entries(:credit_cards).any?
      ].count(true)
    end

    def template_coverage_for_type(template_type)
      templates = templates_for_type(template_type)
      matched = templates.count do |template|
        current_month_entries.any? do |entry|
          template_matches_entry?(template, entry)
        end
      end

      {
        total: templates.size,
        matched: matched,
        remaining: [ templates.size - matched, 0 ].max,
        complete: templates.any? && matched == templates.size
      }
    end

    def matching_template_entries(template_type)
      current_month_entries.select do |entry|
        templates_for_type(template_type).any? do |template|
          template_matches_entry?(template, entry)
        end
      end
    end

    def templates_for_type(template_type)
      case template_type
      when :pay_schedules
        user.pay_schedules.active_only.to_a
      when :subscriptions
        user.subscriptions.active_only.to_a
      when :monthly_bills
        user.monthly_bills.active_only.select { |bill| bill.scheduled_for_month?(current_month.month_on) }
      when :payment_plans
        user.payment_plans.active_only.to_a
      when :credit_cards
        user.credit_cards.active_only.to_a
      else
        []
      end
    end

    def template_matches_entry?(template, entry)
      template.matches_entry_for_month?(entry, month_on: current_month.month_on)
    end
  end
end
