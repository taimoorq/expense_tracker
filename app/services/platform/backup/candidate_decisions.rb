module Platform
  module Backup
    class CandidateDecisions
      FIELDS = %w[key_version merchant_key status evidence_summary reviewed_at].freeze
      COLLECTIONS = { "Subscription" => "subscriptions", "MonthlyBill" => "monthly_bills" }.freeze
      class PartialRestore < ArgumentError; end

      def self.validate_restore_scopes!(user:, scopes:)
        dependencies = %w[accounts planning_templates]
        if (dependencies & scopes).any? && (dependencies - scopes).any? && user.recurring_candidate_decisions.exists?
          raise PartialRestore, "Restore Accounts and Recurring Transactions together to preserve your candidate decisions."
        end
      end

      def self.export_v1(user)
        templates = {
          "subscriptions" => user.subscriptions.order(:due_day, :name, :id).pluck(:id),
          "monthly_bills" => user.monthly_bills.order(:kind, :due_day, :name, :id).pluck(:id)
        }
        decisions = user.recurring_candidate_decisions.includes(:account).to_a
        preload_template_links(decisions)
        decisions.map do |decision|
          template = decision.template
          collection = COLLECTIONS[template&.class&.name]
          decision.attributes.slice(*FIELDS).merge(
            "account_name" => decision.account.name,
            "template_collection" => collection,
            "template_index" => collection && templates.fetch(collection).index(template.id)
          )
        end
      end

      def self.restore_v1(user:, records:, templates:)
        Array(records).each do |record|
          values = record.to_h.deep_symbolize_keys
          account = user.accounts.find_by!(name: values[:account_name])
          template = if values[:template_collection].present?
            collection = templates.fetch(values[:template_collection])
            index = Integer(values[:template_index].to_s, exception: false)
            raise ArgumentError, "The backup contains an invalid recurring candidate reference." unless index && index >= 0
            collection.fetch(index)
          end
          restore!(user: user, account: account, template: template, values: values)
        end
      end

      def self.export_v2(user:, workspace:)
        mappings = workspace.legacy_record_mappings.where(target_record_type: "PlanningTemplate")
          .index_by { |mapping| [ mapping.legacy_record_type, mapping.legacy_record_id ] }
        decisions = user.recurring_candidate_decisions.to_a
        preload_template_links(decisions)
        decisions.map do |decision|
          template = decision.template
          mapping = mappings.fetch([ template.class.name, template.id ]) if template
          {
            external_id: decision.id, attributes: decision.attributes.slice(*FIELDS),
            account_external_id: decision.account_id,
            planning_template_external_id: mapping&.target_record_id
          }
        end
      end

      def self.restore_v2(user:, workspace:, records:, lookup:)
        Array(records).each do |record|
          record = record.to_h.deep_symbolize_keys
          account = lookup.call(:account, record.fetch(:account_external_id))
          if record[:planning_template_external_id].present?
            target = lookup.call(:template, record[:planning_template_external_id])
            mapping = workspace.legacy_record_mappings.find_by!(target_record_type: "PlanningTemplate", target_record_id: target.id)
            collection = COLLECTIONS.fetch(mapping.legacy_record_type)
            template = user.public_send(collection).find(mapping.legacy_record_id)
          else
            template = nil
          end
          restore!(user: user, account: account, template: template, values: record.fetch(:attributes))
        end
      end

      def self.restore!(user:, account:, template:, values:)
        values = values.to_h.stringify_keys.slice(*FIELDS)
        account.recurring_candidate_decisions.create!(values.merge(
          user: user, budget_workspace: account.budget_workspace,
          subscription: template.is_a?(Subscription) ? template : nil,
          monthly_bill: template.is_a?(MonthlyBill) ? template : nil
        ))
      end
      private_class_method :restore!

      def self.preload_template_links(decisions)
        subscriptions = decisions.select { |decision| decision.subscription_id.present? }
        monthly_bills = decisions.select { |decision| decision.monthly_bill_id.present? }
        ActiveRecord::Associations::Preloader.new(records: subscriptions, associations: :subscription).call if subscriptions.any?
        ActiveRecord::Associations::Preloader.new(records: monthly_bills, associations: :monthly_bill).call if monthly_bills.any?
      end
      private_class_method :preload_template_links
    end
  end
end
