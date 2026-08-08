module Planning
  class GeneratePeriod
    def self.call(workspace:, actor_membership:, budget_period:, idempotency_key:)
      new(
        workspace: workspace,
        actor_membership: actor_membership,
        budget_period: budget_period,
        idempotency_key: idempotency_key
      ).call
    end

    def initialize(workspace:, actor_membership:, budget_period:, idempotency_key:)
      @workspace = workspace
      @actor_membership = actor_membership
      @budget_period = budget_period
      @idempotency_key = idempotency_key
    end

    def call
      Identity::WorkspaceAccess.authorize_write!(workspace: workspace, membership: actor_membership)
      raise ArgumentError, "budget period must belong to this workspace" unless budget_period.budget_workspace_id == workspace.id

      Platform::Operations::Executor.call(
        workspace: workspace,
        actor_membership: actor_membership,
        operation_type: "generate_budget_period",
        idempotency_key: idempotency_key,
        request: { budget_period_id: budget_period.id },
        redacted_parameters: { "field_names" => [ "budget_period_id" ] },
        retryable: true,
        on_replay: ->(reference) { BudgetPeriod.find(reference.fetch("id")) }
      ) do |operation|
        budget_period.lock!
        unless budget_period.state_open? || budget_period.state_reopened?
          raise InvalidState, "only an open or reopened period can be generated"
        end

        counts = generate_templates(operation)
        Platform::Operations::Executor::Completion.new(
          value: budget_period,
          result_counts: counts,
          result_reference: { "type" => "BudgetPeriod", "id" => budget_period.id }
        )
      end
    end

    private

    attr_reader :actor_membership, :budget_period, :idempotency_key, :workspace

    def generate_templates(operation)
      counts = { "occurrences" => 0, "budget_items" => 0 }
      workspace.planning_templates
        .active
        .includes(:recurrence_rule, :payment_plan_term, :credit_card_payment_policy)
        .find_each do |template|
        occurrences_for(template).each do |scheduled|
          next unless template_active_on?(template, scheduled.scheduled_on)

          created = materialize(template, scheduled, operation)
          counts["occurrences"] += 1 if created[:occurrence]
          counts["budget_items"] += 1 if created[:item]
        end
      end
      counts
    end

    def occurrences_for(template)
      return [] if template.kind_payment_plan? && planned_amount(template).zero?
      return [] if template.kind_credit_card_payment? && planned_amount(template).zero?

      if template.recurrence_rule.present?
        OccurrenceSchedule.call(rule: template.recurrence_rule, period: budget_period)
      elsif template.kind_credit_card_payment? && template.credit_card_payment_policy.present?
        policy = template.credit_card_payment_policy
        date = Date.new(
          budget_period.starts_on.year,
          budget_period.starts_on.month,
          [ policy.due_day, budget_period.starts_on.end_of_month.day ].min
        )
        [ OccurrenceSchedule::Occurrence.new(scheduled_on: date, slot_key: "credit-card-payment") ]
      else
        []
      end
    end

    def template_active_on?(template, date)
      return false if template.active_from.present? && date < template.active_from
      return false if template.active_until.present? && date > template.active_until

      true
    end

    def materialize(template, scheduled, operation)
      occurrence = RecurringOccurrence.find_or_initialize_by(
        planning_template: template,
        budget_period: budget_period,
        scheduled_on: scheduled.scheduled_on,
        slot_key: scheduled.slot_key
      )
      occurrence_created = occurrence.new_record?
      occurrence.assign_attributes(
        budget_workspace: workspace,
        generation_operation: operation,
        state: occurrence.budget_item_id.present? ? "materialized" : "pending"
      )
      occurrence.save!

      item_created = occurrence.budget_item.blank?
      if item_created
        item = BudgetItem.create!(budget_item_attributes(template, scheduled, occurrence))
        occurrence.update!(budget_item: item, state: "materialized")
        Audit::Recorder.call(
          workspace: workspace,
          actor_membership: actor_membership,
          operation_run: operation,
          entity: occurrence,
          action: "generate",
          changed_fields: %i[planning_template budget_period scheduled_on budget_item]
        )
      end

      { occurrence: occurrence_created, item: item_created }
    end

    def budget_item_attributes(template, scheduled, occurrence)
      {
        budget_workspace: workspace,
        budget_period: budget_period,
        category: template.category,
        recurring_occurrence: occurrence,
        scheduled_on: scheduled.scheduled_on,
        flow_kind: template.flow_kind,
        budget_group: template.budget_group,
        planned_amount: planned_amount(template),
        currency_code: workspace.default_currency_code,
        state: "open",
        name_snapshot: template.name,
        payee_snapshot: template.name,
        category_snapshot: template.category&.name,
        intended_source_account: template.source_account,
        intended_destination_account: template.destination_account,
        priority_classification: "need",
        origin_kind: "recurring",
        notes: template.notes
      }
    end

    def planned_amount(template)
      if template.kind_payment_plan? && template.payment_plan_term.present?
        term = template.payment_plan_term
        progress = term.opening_paid_adjustment + allocated_progress(template)
        remaining = [ term.total_due - progress, 0 ].max
        [ term.monthly_target, remaining ].min
      elsif template.kind_credit_card_payment? && template.credit_card_payment_policy.present?
        template.credit_card_payment_policy.minimum_payment
      else
        template.default_amount
      end
    end

    def allocated_progress(template)
      BudgetAllocation
        .joins(:financial_transaction, budget_item: :recurring_occurrence)
        .where(recurring_occurrences: { planning_template_id: template.id })
        .where(financial_transactions: { state: "posted" })
        .sum(:amount)
    end

    class InvalidState < StandardError; end
  end
end
