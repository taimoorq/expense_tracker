module Overview
  class TemplateSummary
    TEMPLATE_TYPES = %i[pay_schedules subscriptions monthly_bills payment_plans credit_cards].freeze

    def initialize(user:, current_month:, current_month_entries:)
      @user = user
      @current_month = current_month
      @current_month_entries = current_month_entries
    end

    def call
      count_pairs = TEMPLATE_TYPES.to_h { |template_type| [ template_type, count_pair_for(template_type) ] }
      counts = count_pairs.transform_values { |pair| pair.fetch(:total) }
      linked_counts = count_pairs.transform_values { |pair| pair.fetch(:linked) }

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

    def count_pair_for(template_type)
      if current_month
        templates = all_templates_by_type.fetch(template_type)
        return {
          total: templates.size,
          linked: templates.count { |template| template.linked_account_id.present? }
        }
      end

      total, linked = user.public_send(template_type).unscope(:order).pick(
        Arel.sql("COUNT(*)"),
        Arel.sql("COUNT(linked_account_id)")
      )

      { total: total.to_i, linked: linked.to_i }
    end

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
      coverage_summaries = templates_for_type(template_type).map do |template|
        Recurring::MonthTemplateCoverage
          .new(template: template, budget_month: current_month, entries: current_month_entries)
          .summary
      end
      total = coverage_summaries.sum { |summary| summary.fetch(:total) }
      matched = coverage_summaries.sum { |summary| summary.fetch(:matched) }

      {
        total: total,
        matched: matched,
        remaining: [ total - matched, 0 ].max,
        complete: total.positive? && matched == total
      }
    end

    def matching_template_entries(template_type)
      templates = templates_for_type(template_type)
      current_month_entries.select do |entry|
        templates.any? do |template|
          template_matches_entry?(template, entry)
        end
      end
    end

    def templates_for_type(template_type)
      @templates_by_type ||= {}
      return @templates_by_type.fetch(template_type) if @templates_by_type.key?(template_type)

      records = all_templates_by_type.fetch(template_type)
      @templates_by_type[template_type] = case template_type
      when :pay_schedules
        records.select { |template| pay_schedule_active_during_month?(template) }.sort_by(&:name)
      when :subscriptions, :payment_plans
        records.select(&:active?).sort_by { |template| [ template.due_day, template.name ] }
      when :monthly_bills
        records.select { |template| template.active? && template.scheduled_for_month?(current_month.month_on) }
          .sort_by { |template| [ template.due_day, template.name ] }
      when :credit_cards
        records.select(&:active?).sort_by { |template| [ template.priority, template.name ] }
      else
        []
      end
    end

    def all_templates_by_type
      @all_templates_by_type ||= begin
        records = TEMPLATE_TYPES.to_h do |template_type|
          [ template_type, user.public_send(template_type).unscope(:order).to_a ]
        end
        linked_templates = records.values_at(:pay_schedules, :subscriptions, :monthly_bills, :payment_plans).flatten
        ActiveRecord::Associations::Preloader.new(records: linked_templates, associations: :linked_account).call if linked_templates.any?
        cards = records.fetch(:credit_cards)
        ActiveRecord::Associations::Preloader.new(records: cards, associations: :payment_account).call if cards.any?
        records
      end
    end

    def pay_schedule_active_during_month?(template)
      month_start = current_month.month_on.beginning_of_month
      month_end = current_month.month_on.end_of_month
      template.active? && template.first_pay_on <= month_end &&
        (template.ends_on.blank? || template.ends_on >= month_start)
    end

    def template_matches_entry?(template, entry)
      template.matches_entry_for_month?(entry, month_on: current_month.month_on)
    end
  end
end
