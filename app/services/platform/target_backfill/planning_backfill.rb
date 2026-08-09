module Platform
  module TargetBackfill
    class PlanningBackfill
      TEMPLATE_MODELS = [ PaySchedule, Subscription, MonthlyBill, PaymentPlan, CreditCard ].freeze
      Result = Data.define(:workspace, :operation_run, :counts) do
        def as_json(*)
          { workspace_id: workspace.id, operation_run_id: operation_run.id, counts: counts }
        end
      end

      def self.call(user:)
        new(user: user).call
      end

      def initialize(user:)
        @user = user
      end

      def call
        bootstrap = WorkspaceBootstrap.call(user: user)
        @workspace = bootstrap.workspace
        @operation_run = bootstrap.operation_run
        @mapping_store = MappingStore.new(workspace: workspace, operation_run: operation_run)
        @counts = Hash.new(0)

        map_accounts
        backfill_periods
        backfill_templates
        backfill_items
        backfill_occurrences
        persist_counts

        Result.new(workspace: workspace, operation_run: operation_run, counts: counts)
      end

      private

      attr_reader :counts, :mapping_store, :operation_run, :user, :workspace

      def map_accounts
        user.accounts.find_each do |account|
          mapping_store.record!(
            source: account,
            target: account,
            source_attributes: account.attributes.slice("name", "kind", "active", "include_in_cash", "include_in_net_worth")
          )
          counts["accounts"] += 1
        end
      end

      def backfill_periods
        user.budget_months.find_each do |month|
          ApplicationRecord.transaction do
            period = mapping_store.target_for(source: month, target_class: BudgetPeriod) ||
              BudgetPeriod.find_or_initialize_by(budget_workspace: workspace, starts_on: month.month_on)
            period.assign_attributes(currency_code: currency_code, notes: month.notes, state: "open")
            period.save!
            mapping_store.record!(
              source: month,
              target: period,
              source_attributes: month.attributes.slice("month_on", "notes", "leftover")
            )
            counts["budget_periods"] += 1
          end
        end
      end

      def backfill_templates
        TEMPLATE_MODELS.each do |model|
          model.where(user_id: user.id).find_each { |source| backfill_template(source) }
        end
      end

      def backfill_template(source)
        ApplicationRecord.transaction do
          template = mapping_store.target_for(source: source, target_class: PlanningTemplate) || build_template(source)
          template.assign_attributes(template_attributes(source))
          template.save!
          backfill_template_detail(source, template)
          mapping_store.record!(source: source, target: template, source_attributes: template_source_attributes(source))
          counts["planning_templates"] += 1
        end
      end

      def build_template(source)
        target_id = PlanningTemplate.exists?(id: source.id) ? SecureRandom.uuid : source.id
        if target_id != source.id
          mapping_store.record_discrepancy!(source: source, code: "planning_template_id_collision")
        end
        PlanningTemplate.new(id: target_id, budget_workspace: workspace)
      end

      def template_attributes(source)
        Platform::TargetTranslation::PlanningTemplate.attributes(source: source, workspace: workspace)
      end

      def backfill_template_detail(source, template)
        case source
        when CreditCard
          backfill_credit_card_policy(source, template)
        else
          backfill_recurrence_rule(source, template)
          backfill_payment_plan_term(source, template) if source.is_a?(PaymentPlan)
        end
      end

      def backfill_recurrence_rule(source, template)
        rule = RecurrenceRule.find_or_initialize_by(planning_template: template)
        rule.assign_attributes(Platform::TargetTranslation::PlanningTemplate.recurrence_attributes(source))
        rule.save!

        Platform::TargetTranslation::PlanningTemplate.allowed_months(source).each do |month_number|
          rule.recurrence_months.find_or_create_by!(month_number: month_number)
        end
        if source.is_a?(MonthlyBill)
          rule.recurrence_months.where.not(
            month_number: Platform::TargetTranslation::PlanningTemplate.allowed_months(source)
          ).delete_all
        end
      end

      def backfill_payment_plan_term(source, template)
        term = PaymentPlanTerm.find_or_initialize_by(planning_template: template)
        term.assign_attributes(Platform::TargetTranslation::PlanningTemplate.payment_plan_term_attributes(source))
        term.save!
      end

      def backfill_credit_card_policy(source, template)
        if source.linked_account.blank? || source.payment_account.blank?
          mapping_store.record_discrepancy!(source: source, code: "credit_card_policy_missing_account")
          return
        end

        policy = CreditCardPaymentPolicy.find_or_initialize_by(planning_template: template)
        policy.assign_attributes(
          Platform::TargetTranslation::PlanningTemplate.credit_card_policy_attributes(source, workspace: workspace)
        )
        policy.save!
      end

      def backfill_items
        user.expense_entries.includes(:budget_month).find_each do |entry|
          ApplicationRecord.transaction do
            period = mapped_target!(entry.budget_month, BudgetPeriod)
            item = mapping_store.target_for(source: entry, target_class: BudgetItem) || BudgetItem.new
            item.assign_attributes(item_attributes(entry, period))
            item.save!
            mapping_store.record!(source: entry, target: item, source_attributes: item_source_attributes(entry))
            counts["budget_items"] += 1
          end
        end
      end

      def item_attributes(entry, period)
        Platform::TargetTranslation::ExpenseEntry.call(
          entry: entry,
          workspace: workspace,
          period: period,
          category: normalized_category(entry)
        )
      end

      def normalized_category(entry)
        return if entry.category.blank?

        category = Platform::TargetSync::CategoryResolver.call(
          workspace: workspace,
          name: entry.category.strip,
          flow_kind: Platform::TargetTranslation::ExpenseEntry.flow_kind(entry),
          budget_group: Platform::TargetTranslation::ExpenseEntry.budget_group(entry)
        )
        return category if category.flow_kind == Platform::TargetTranslation::ExpenseEntry.flow_kind(entry)

        mapping_store.record_discrepancy!(source: entry, code: "category_semantics_conflict")
        nil
      end

      def backfill_occurrences
        user.expense_entries
          .where.not(source_template_id: nil)
          .where.not(generated_entry_key: nil)
          .includes(:source_template, :budget_month)
          .find_each do |entry|
            template = mapping_store.target_for(source: entry.source_template, target_class: PlanningTemplate)
            next if template.blank?

            ApplicationRecord.transaction do
              period = mapped_target!(entry.budget_month, BudgetPeriod)
              item = mapped_target!(entry, BudgetItem)
              occurrence = mapping_store.target_for(source: entry, target_class: RecurringOccurrence) ||
                RecurringOccurrence.find_or_initialize_by(
                  planning_template: template,
                  budget_period: period,
                  scheduled_on: entry.occurred_on,
                  slot_key: "default"
                )
              occurrence.assign_attributes(
                budget_workspace: workspace,
                budget_item: item,
                state: "materialized",
                generation_operation: operation_run
              )
              occurrence.save!
              item.update!(recurring_occurrence: occurrence) if item.recurring_occurrence_id != occurrence.id
              mapping_store.record!(
                source: entry,
                target: occurrence,
                source_attributes: entry.attributes.slice("generated_entry_key", "occurred_on", "source_template_type", "source_template_id")
              )
              counts["recurring_occurrences"] += 1
            end
          end
      end

      def mapped_target!(source, target_class)
        mapping_store.target_for(source: source, target_class: target_class) ||
          raise(MappingStore::MappingConflict, "Missing #{target_class.name} mapping for #{source.class.name} #{source.id}")
      end

      def template_source_attributes(source)
        source.attributes.except("created_at", "updated_at", "lock_version")
      end

      def item_source_attributes(entry)
        entry.attributes.except("created_at", "updated_at", "lock_version")
      end

      def currency_code
        workspace.default_currency_code
      end

      def persist_counts
        operation_run.update!(result_counts: operation_run.result_counts.merge("planning_backfill" => counts))
      end
    end
  end
end
