require "digest"

module Platform
  module Backup
    module V2
      class LegacyProjection
        MAPPING_VERSION = "backup-v2-compat-v1".freeze

        def initialize(user:, workspace:, operation_run:)
          @user = user
          @workspace = workspace
          @mapping_store = Platform::TargetBackfill::MappingStore.new(
            workspace: workspace,
            operation_run: operation_run,
            version: MAPPING_VERSION
          )
          @counts = Hash.new(0)
          @legacy_templates = {}
          @legacy_months = {}
          @legacy_entries = {}
          @legacy_imports = {}
        end

        def call
          project_templates
          project_months
          project_entries
          project_snapshots
          project_imports
          counts
        end

        private

        attr_reader :counts, :legacy_entries, :legacy_imports, :legacy_months, :legacy_templates,
          :mapping_store, :user, :workspace

        def project_templates
          workspace.planning_templates.includes(
            :payment_plan_term,
            :credit_card_payment_policy,
            recurrence_rule: :recurrence_months
          ).find_each do |template|
            legacy = build_legacy_template(template)
            legacy.save!
            legacy_templates[template.id] = legacy
            record_mapping(legacy, template)
            counts["legacy_planning_templates"] += 1
          end
        end

        def build_legacy_template(template)
          case template.kind
          when "paycheck" then build_pay_schedule(template)
          when "subscription" then build_subscription(template)
          when "bill" then build_monthly_bill(template)
          when "payment_plan" then build_payment_plan(template)
          when "credit_card_payment" then build_credit_card(template)
          else raise ProjectionError, "Backup V2 contains an unsupported planning template kind."
          end
        end

        def common_template_attributes(template)
          {
            user: user,
            budget_workspace: workspace,
            name: template.name,
            active: template.archived_at.blank?,
            account: template.source_account&.name,
            linked_account: template.kind_credit_card_payment? ? template.destination_account : template.source_account,
            created_at: template.created_at,
            updated_at: template.updated_at
          }
        end

        def build_pay_schedule(template)
          rule = required_rule(template)
          PaySchedule.new(common_template_attributes(template).merge(
            amount: template.default_amount,
            cadence: pay_schedule_cadence(rule),
            first_pay_on: rule.starts_on,
            ends_on: rule.ends_on,
            day_of_month_one: rule.day_one,
            day_of_month_two: rule.day_two,
            weekend_adjustment: rule.weekend_policy_none? ? "no_adjustment" : rule.weekend_policy
          ))
        end

        def pay_schedule_cadence(rule)
          return "biweekly" if rule.cadence_weekly? && rule.interval_count == 2
          return "weekly" if rule.cadence_weekly?
          return "semimonthly" if rule.day_two.present?

          "monthly"
        end

        def build_subscription(template)
          rule = required_rule(template)
          Subscription.new(common_template_attributes(template).merge(
            amount: template.default_amount,
            due_day: due_day(rule),
            notes: template.notes
          ))
        end

        def build_monthly_bill(template)
          rule = required_rule(template)
          frequency, months = legacy_billing_schedule(rule)
          MonthlyBill.new(common_template_attributes(template).merge(
            kind: template.budget_group_variable? ? "variable_bill" : "fixed_payment",
            default_amount: template.default_amount,
            due_day: due_day(rule),
            billing_frequency: frequency,
            billing_months: months,
            notes: template.notes
          ))
        end

        def legacy_billing_schedule(rule)
          months = rule.recurrence_months.order(:month_number).pluck(:month_number)
          return [ "monthly", (1..12).to_a ] if months.empty? || months.size == 12
          return [ "quarterly", months ] if months.size == 4
          return [ "semiannual", months ] if months.size == 2
          return [ "annual", months ] if months.size == 1

          raise ProjectionError, "A restored billing schedule cannot be represented by the compatibility workflow."
        end

        def build_payment_plan(template)
          rule = required_rule(template)
          term = template.payment_plan_term || raise(ProjectionError, "A restored payment plan is missing its terms.")
          PaymentPlan.new(common_template_attributes(template).merge(
            total_due: term.total_due,
            amount_paid: term.opening_paid_adjustment,
            monthly_target: term.monthly_target,
            due_day: due_day(rule),
            notes: template.notes
          ))
        end

        def build_credit_card(template)
          policy = template.credit_card_payment_policy || raise(ProjectionError, "A restored credit-card payment is missing its policy.")
          CreditCard.new(common_template_attributes(template).merge(
            account: policy.payment_account&.name,
            linked_account: policy.liability_account,
            payment_account: policy.payment_account,
            minimum_payment: policy.minimum_payment,
            due_day: policy.due_day,
            priority: policy.priority,
            notes: template.notes
          ))
        end

        def required_rule(template)
          template.recurrence_rule || raise(ProjectionError, "A restored planning template is missing its recurrence rule.")
        end

        def due_day(rule)
          rule.day_one || rule.anchor_on&.day || 1
        end

        def project_months
          workspace.budget_periods.order(:starts_on).find_each do |period|
            month = user.budget_months.create!(
              budget_workspace: workspace,
              month_on: period.starts_on,
              label: period.starts_on.strftime("%B %Y"),
              notes: period.notes,
              created_at: period.created_at,
              updated_at: period.updated_at
            )
            legacy_months[period.id] = month
            record_mapping(month, period)
            counts["legacy_budget_months"] += 1
          end
        end

        def project_entries
          allocation_totals = posted_allocation_totals
          first_transactions = first_allocated_transactions
          workspace.budget_items.includes(:category, :recurring_occurrence).order(:created_at).find_each do |item|
            entry = build_legacy_entry(item, allocation_totals.fetch(item.id, 0).to_d)
            entry.save!
            legacy_entries[item.id] = entry
            record_mapping(entry, item)
            record_mapping(entry, item.recurring_occurrence) if item.recurring_occurrence.present?
            transaction = first_transactions[item.id]
            record_mapping(entry, transaction) if transaction.present?
            counts["legacy_expense_entries"] += 1
          end
        end

        def build_legacy_entry(item, actual_amount)
          template = legacy_templates[item.recurring_occurrence&.planning_template_id]
          status = if item.state.in?(%w[skipped cancelled voided])
            "skipped"
          elsif actual_amount.positive?
            "paid"
          else
            "planned"
          end
          ExpenseEntry.new(
            user: user,
            budget_workspace: workspace,
            budget_month: legacy_months.fetch(item.budget_period_id),
            source_account: item.intended_source_account,
            destination_account: item.intended_destination_account,
            occurred_on: item.scheduled_on || item.budget_period.starts_on,
            section: legacy_section(item),
            category: item.category&.name.presence || item.category_snapshot,
            payee: item.payee_snapshot.presence || item.name_snapshot,
            planned_amount: item.planned_amount,
            actual_amount: actual_amount.positive? ? actual_amount : nil,
            status: status,
            need_or_want: item.priority_classification.to_s.humanize,
            notes: item.notes,
            account: item.intended_source_account&.name,
            source_file: template&.template_source_file || "backup_v2",
            source_template: template,
            generated_entry_key: item.recurring_occurrence_id.present? ? "backup-v2:#{item.recurring_occurrence_id}" : nil,
            created_at: item.created_at,
            updated_at: item.updated_at
          )
        end

        def legacy_section(item)
          return "income" if item.flow_kind_income?
          return item.budget_group if item.budget_group.in?(%w[fixed variable debt])

          "other"
        end

        def posted_allocation_totals
          workspace.budget_allocations
            .joins(:financial_transaction)
            .where(financial_transactions: { state: "posted" })
            .group(:budget_item_id)
            .sum(:amount)
        end

        def first_allocated_transactions
          workspace.budget_allocations
            .joins(:financial_transaction)
            .where(financial_transactions: { state: "posted" })
            .order(:created_at)
            .each_with_object({}) { |allocation, values| values[allocation.budget_item_id] ||= allocation.financial_transaction }
        end

        def project_snapshots
          workspace.balance_observations.status_trusted.order(:effective_through_at, :created_at).find_each do |observation|
            recorded_on = observation.effective_through_at.to_date
            snapshot = observation.account.account_snapshots.find_or_initialize_by(recorded_on: recorded_on)
            snapshot.assign_attributes(
              balance: observation.balance,
              available_balance: observation.available_balance,
              notes: observation.notes,
              created_at: observation.created_at,
              updated_at: observation.updated_at
            )
            snapshot.save!
            record_mapping(snapshot, observation)
            counts["legacy_account_snapshots"] += 1
          end
        end

        def project_imports
          workspace.import_batches.includes(:account, :import_profile).order(:created_at).find_each do |batch|
            next if batch.account.blank?

            legacy_import = user.account_activity_imports.create!(
              budget_workspace: workspace,
              account: batch.account,
              original_filename: batch.original_filename.presence || "restored-import.csv",
              amount_strategy: batch.import_profile&.amount_strategy.presence || "charges_are_negative",
              header_row_number: batch.import_profile&.header_row_number || 1,
              column_mapping: batch.import_profile&.column_mapping || {},
              file_digest: batch.file_digest,
              commit_idempotency_key: legacy_import_key(batch.idempotency_key),
              rows_count: batch.row_count,
              imported_count: batch.imported_count,
              duplicate_count: batch.duplicate_count,
              started_on: batch.coverage_starts_on,
              ended_on: batch.coverage_ends_on,
              warning_messages: batch.warnings,
              metadata: batch.redacted_metadata,
              created_at: batch.created_at,
              updated_at: batch.updated_at
            )
            legacy_imports[batch.id] = legacy_import
            record_mapping(legacy_import, batch)
            counts["legacy_account_activity_imports"] += 1
          end
          project_import_rows
        end

        def project_import_rows
          workspace.import_rows.includes(:financial_transaction).order(:import_batch_id, :row_number).find_each do |row|
            transaction = row.financial_transaction
            legacy_import = legacy_imports[row.import_batch_id]
            next if transaction.blank? || legacy_import.blank?

            posting = transaction.account_postings.find_by(account_id: legacy_import.account_id) || transaction.account_postings.first
            next if posting.blank?

            entry = allocated_legacy_entry(transaction)
            activity = user.account_activities.create!(
              budget_workspace: workspace,
              account: posting.account,
              account_activity_import: legacy_import,
              expense_entry: entry,
              transaction_on: transaction.effective_on,
              posted_on: transaction.posted_on,
              description: transaction.description,
              memo: transaction.memo,
              category: transaction.category&.name,
              activity_type: row.normalized_payload.to_h["activity_type"],
              amount: transaction.gross_amount,
              raw_amount: transaction.gross_amount,
              account_delta: posting.amount,
              fingerprint: row.fingerprint,
              row_number: row.row_number,
              raw_payload: row.raw_payload,
              created_at: row.created_at,
              updated_at: row.updated_at
            )
            record_mapping(activity, transaction)
            counts["legacy_account_activities"] += 1
          end
        end

        def allocated_legacy_entry(transaction)
          item_id = transaction.budget_allocations.order(:created_at).pick(:budget_item_id)
          legacy_entries[item_id]
        end

        def legacy_import_key(value)
          candidate = value.to_s
          return candidate if candidate.match?(/\A[0-9a-f]{64}\z/)

          Digest::SHA256.hexdigest("backup-v2:#{candidate}")
        end

        def record_mapping(source, target)
          mapping_store.record!(
            source: source,
            target: target,
            source_attributes: source.attributes.except("created_at", "updated_at", "lock_version")
          )
        end

        class ProjectionError < StandardError; end
      end
    end
  end
end
