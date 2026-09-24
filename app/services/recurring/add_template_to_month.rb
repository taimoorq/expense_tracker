require "digest"

module Recurring
  class AddTemplateToMonth
    class Invalid < StandardError; end
    Result = Data.define(:status, :entry, :date, :amount, :digest)

    def initialize(user:, template:, budget_month:)
      @user, @template, @budget_month = user, template, budget_month
    end

    def preview
      authorize!
      result
    end

    def call(expected_digest:)
      authorize!
      # Normal generation also locks the legacy month; closing locks the target period.
      budget_month.with_lock do
        template.lock!
        target_period&.lock!
        check_period!
        current = result
        next current if current.status == :already_present
        raise Invalid, "This recurring transaction is not scheduled in the selected month." if current.status == :not_scheduled
        raise Invalid, "The recurring transaction changed. Review the month preview again." unless current.digest == expected_digest

        if budget_month.budget_workspace&.target_writes_enabled?
          Platform::TargetSync::PlanningTemplateWriter.call(source: template)
        end
        generator = GenerateMonthRecurringEntries.new(budget_month: budget_month, templates: [ template ])
        generator.call
        entry = budget_month.expense_entries.find_by!(generated_entry_key: template.generated_entry_key(month_on: budget_month.month_on, occurred_on: current.date))
        entry.update!(source_account: template.linked_account, destination_account: nil)
        Platform::TargetSync::ExpenseEntryWriter.call(entry: entry)
        Result.new(status: :added, entry: entry, date: entry.occurred_on, amount: entry.planned_amount, digest: current.digest)
      end
    ensure
      budget_month.expense_entries.reset
    end

    private

    attr_reader :user, :template, :budget_month

    def authorize!
      unless template.is_a?(Subscription) || template.is_a?(MonthlyBill)
        raise Invalid, "Choose a subscription or monthly bill."
      end
      unless template.user_id == user.id && budget_month.user_id == user.id && template.budget_workspace_id == budget_month.budget_workspace_id
        raise ActiveRecord::RecordNotFound
      end
      linked_account = template.linked_account
      if linked_account && (linked_account.user_id != user.id || linked_account.budget_workspace_id != template.budget_workspace_id)
        raise Invalid, "The activity account must belong to this recurring transaction's workspace."
      end
      workspace = budget_month.budget_workspace
      if workspace
        Identity::WorkspaceAccess.authorize_write!(workspace: workspace, membership: workspace.workspace_memberships.find_by(user: user))
        Platform::TargetSync::Context.for(budget_month)
      end
      raise Invalid, "Activate the recurring transaction before adding it to a month." unless template.active?
      check_period!
    end

    def target_period
      workspace = budget_month.budget_workspace
      return unless workspace
      workspace.budget_periods.find_by(starts_on: budget_month.month_on)
    end

    def check_period!
      period = target_period
      workspace = budget_month.budget_workspace
      if workspace && (workspace.target_reads_enabled? || workspace.target_writes_enabled?) && period.blank?
        raise Invalid, "This month's planning records are not synchronized yet."
      end
      raise Invalid, "Reopen this month before adding to its plan." if period && !period.state.in?(%w[open reopened])
      raise Invalid, "Activate the recurring transaction before adding it to a month." unless template.active?
    end

    def result
      entries = budget_month.expense_entries.to_a
      existing = entries.find { |entry| entry.source_template_type == template.class.name && entry.source_template_id == template.id }
      coverage = MonthTemplateCoverage.new(template: template, budget_month: budget_month, entries: entries)
      existing ||= coverage.matched_rows.first&.entry
      date = template.recurring_month_occurrences(budget_month.month_on).first
      amount = template.is_a?(Subscription) ? template.amount : template.default_amount
      digest = Digest::SHA256.hexdigest(Platform::CanonicalJson.dump(
        template: template.attributes, month: budget_month.id, date: date, amount: amount
      ))
      Result.new(status: existing ? :already_present : (date ? :missing : :not_scheduled), entry: existing, date: date, amount: amount, digest: digest)
    end
  end
end
