module Platform
  module Backup
    module V1
      class Importer
        SCOPES = Platform::UserDataExport::SCOPES

        def initialize(user:, payload:, scopes:)
          @user = user
          @payload = payload.deep_symbolize_keys
          @scopes = Array(scopes).map(&:to_s) & SCOPES
        end

        def call
          return failure("Choose at least one section to import.") if scopes.empty?

          data = payload.fetch(:data, {})
          missing_scope = scopes.find { |scope| required_scope?(scope) && !data.key?(scope.to_sym) }
          return failure("The backup file does not include #{missing_scope.humanize.downcase}.") if missing_scope

          counts = {}

          ApplicationRecord.transaction do
            capture_account_reference_names if scopes.include?("accounts")
            clear_selected_data
            counts[:accounts] = import_accounts(data[:accounts]) if scopes.include?("accounts")
            counts[:planning_templates] = import_planning_templates(data[:planning_templates]) if scopes.include?("planning_templates")
            counts[:budget_months] = import_budget_months(data[:budget_months]) if scopes.include?("budget_months")
            counts[:preferences] = import_preferences(data[:preferences]) if scopes.include?("preferences") && data.key?(:preferences)
            relink_planning_template_accounts(data)
            relink_expense_entry_provenance
          end

          { success: true, counts: counts }
        rescue ActiveRecord::RecordInvalid => error
          failure(error.record.errors.full_messages.to_sentence.presence || error.message)
        end

        private

        attr_reader :payload, :scopes, :user

        def required_scope?(scope)
          scope != "preferences"
        end

        def clear_selected_data
          clear_planning_templates if scopes.include?("planning_templates")
          user.budget_months.destroy_all if scopes.include?("budget_months")
          unlink_account_references if scopes.include?("accounts")
          user.accounts.destroy_all if scopes.include?("accounts")
        end

        def capture_account_reference_names
          @preserved_planning_template_data = {
            pay_schedules: user.pay_schedules.includes(:linked_account).map { |record| template_account_names(record) },
            subscriptions: user.subscriptions.includes(:linked_account).map { |record| template_account_names(record) },
            monthly_bills: user.monthly_bills.includes(:linked_account).map { |record| template_account_names(record) },
            payment_plans: user.payment_plans.includes(:linked_account).map { |record| template_account_names(record) },
            credit_cards: user.credit_cards.includes(:linked_account, :payment_account).map do |record|
              {
                name: record.name,
                payment_account: record.payment_account&.name || record.account,
                linked_account: record.linked_account&.name
              }
            end
          }

          @preserved_entry_account_names = user.expense_entries.includes(:source_account, :destination_account).each_with_object({}) do |entry, lookup|
            lookup[entry.id] = {
              source_account: entry.source_account&.name || entry.account,
              destination_account: entry.destination_account&.name
            }
          end
        end

        def template_account_names(record)
          {
            name: record.name,
            account: record.linked_account&.name || record.account
          }
        end

        def clear_planning_templates
          user.pay_schedules.destroy_all
          user.subscriptions.destroy_all
          user.monthly_bills.destroy_all
          user.payment_plans.destroy_all
          user.credit_cards.destroy_all
        end

        def unlink_account_references
          unlink_planning_template_account_references unless scopes.include?("planning_templates")
          unlink_expense_entry_account_references unless scopes.include?("budget_months")
        end

        def unlink_planning_template_account_references
          user.pay_schedules.update_all(linked_account_id: nil)
          user.subscriptions.update_all(linked_account_id: nil)
          user.monthly_bills.update_all(linked_account_id: nil)
          user.payment_plans.update_all(linked_account_id: nil)
          user.credit_cards.update_all(linked_account_id: nil, payment_account_id: nil)
        end

        def unlink_expense_entry_account_references
          user.expense_entries.update_all(source_account_id: nil, destination_account_id: nil)
        end

        def import_planning_templates(data)
          {
            pay_schedules: Array(data[:pay_schedules]).count do |attributes|
              user.pay_schedules.create!(attributes.slice(:name, :cadence, :amount, :first_pay_on, :ends_on, :day_of_month_one, :day_of_month_two, :weekend_adjustment, :account, :active))
            end,
            subscriptions: Array(data[:subscriptions]).count do |attributes|
              user.subscriptions.create!(attributes.slice(:name, :amount, :due_day, :account, :notes, :active))
            end,
            monthly_bills: Array(data[:monthly_bills]).count do |attributes|
              user.monthly_bills.create!(attributes.slice(:name, :kind, :default_amount, :due_day, :billing_frequency, :billing_months, :account, :notes, :active))
            end,
            payment_plans: Array(data[:payment_plans]).count do |attributes|
              user.payment_plans.create!(attributes.slice(:name, :total_due, :amount_paid, :monthly_target, :due_day, :account, :notes, :active))
            end,
            credit_cards: Array(data[:credit_cards]).count do |attributes|
              payment_account_name = attributes[:payment_account].presence || attributes[:account]
              user.credit_cards.create!(
                attributes.slice(:name, :minimum_payment, :due_day, :priority, :notes, :active).merge(
                  account: payment_account_name,
                  payment_account: user.accounts.find_by(name: payment_account_name),
                  linked_account: user.accounts.find_by(name: attributes[:linked_account])
                )
              )
            end
          }
        end

        def import_budget_months(data)
          month_count = 0
          entry_count = 0

          Array(data).each do |attributes|
            month = user.budget_months.create!(attributes.slice(:label, :month_on, :leftover, :notes))
            month_count += 1

            Array(attributes[:expense_entries]).each do |entry_attributes|
              entry = month.expense_entries.create!(
                entry_attributes.slice(
                  :occurred_on,
                  :section,
                  :category,
                  :payee,
                  :planned_amount,
                  :actual_amount,
                  :account,
                  :status,
                  :auto_completed_at,
                  :need_or_want,
                  :notes,
                  :source_file
                ).merge(
                  source_account: account_named(entry_attributes[:source_account]),
                  destination_account: account_named(entry_attributes[:destination_account])
                )
              )
              Budgeting::ExpenseEntryProvenanceRepair.new(
                entry: entry,
                source_template_type: entry_attributes[:source_template_type],
                source_template_name: entry_attributes[:source_template_name]
              ).repair!
              restore_generated_entry_key(entry, entry_attributes)
              restore_entry_timestamps(entry, entry_attributes)
              entry_count += 1
            end
          end

          { months: month_count, entries: entry_count }
        end

        def import_accounts(data)
          account_count = 0
          snapshot_count = 0

          Array(data).each do |attributes|
            account = user.accounts.create!(attributes.slice(:name, :institution_name, :kind, :active, :include_in_net_worth, :include_in_cash, :notes))
            account_count += 1

            Array(attributes[:account_snapshots]).each do |snapshot_attributes|
              account.account_snapshots.create!(snapshot_attributes.slice(:recorded_on, :balance, :available_balance, :notes))
              snapshot_count += 1
            end
          end

          { accounts: account_count, snapshots: snapshot_count }
        end

        def import_preferences(data)
          attributes = (data || {}).to_h.slice(:default_landing_page, :preferred_month_view, :financial_rhythm).compact
          return { preferences: 0 } if attributes.empty?

          user.update!(attributes)
          { preferences: attributes.size }
        end

        def relink_planning_template_accounts(data)
          return unless scopes.include?("planning_templates") || scopes.include?("accounts")

          Recurring::PlanningTemplateAccountLinking.relink_for(
            user,
            planning_template_data: data[:planning_templates].presence || @preserved_planning_template_data
          )
        end

        def relink_expense_entry_provenance
          return unless scopes.include?("budget_months") || scopes.include?("accounts")

          Budgeting::ExpenseEntryProvenanceRepair.relink_for(user)
          relink_preserved_entry_account_references if scopes.include?("accounts") && !scopes.include?("budget_months")
        end

        def relink_preserved_entry_account_references
          return if @preserved_entry_account_names.blank?

          user.expense_entries.find_each do |entry|
            preserved_names = @preserved_entry_account_names[entry.id]
            next if preserved_names.blank?

            source_account = account_named(preserved_names[:source_account])
            destination_account = account_named(preserved_names[:destination_account])

            entry.source_account = source_account if entry.source_account.blank? && source_account.present?
            entry.destination_account = destination_account if entry.destination_account.blank? && destination_account.present?
            entry.save! if entry.changed?
          end
        end

        def restore_generated_entry_key(entry, entry_attributes)
          canonical_key = canonical_generated_entry_key(entry)
          exported_key = entry_attributes[:generated_entry_key].presence
          restored_key = canonical_key || portable_exported_generated_key(entry, exported_key)
          return if restored_key.blank?

          entry.update!(generated_entry_key: restored_key)
        end

        def canonical_generated_entry_key(entry)
          template = entry.source_template
          return if template.blank?

          if template.is_a?(CreditCard) && entry.source_file == CreditCard.template_source_file
            template.estimated_entry_key(month_on: entry.budget_month.month_on)
          elsif entry.generated_from_template? && template.respond_to?(:generated_entry_key) && entry.occurred_on.present?
            template.generated_entry_key(month_on: entry.budget_month.month_on, occurred_on: entry.occurred_on)
          end
        end

        def portable_exported_generated_key(entry, exported_key)
          return if exported_key.blank?
          return if entry.source_file == CreditCard.template_source_file

          exported_key
        end

        def restore_entry_timestamps(entry, entry_attributes)
          timestamp_updates = {
            created_at: parse_time(entry_attributes[:created_at]),
            updated_at: parse_time(entry_attributes[:updated_at])
          }.compact
          return if timestamp_updates.empty?

          entry.update_columns(timestamp_updates)
        end

        def parse_time(value)
          return if value.blank?

          Time.zone.parse(value.to_s)
        rescue ArgumentError
          nil
        end

        def account_named(name)
          return if name.blank?

          account_by_name[name]
        end

        def account_by_name
          @account_by_name ||= user.accounts.index_by(&:name)
        end

        def failure(message)
          { success: false, error: message }
        end
      end
    end
  end
end
