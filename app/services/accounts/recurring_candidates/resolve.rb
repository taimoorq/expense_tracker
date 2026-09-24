require "digest"

module Accounts
  module RecurringCandidates
    class Resolve
      class Invalid < StandardError; end

      def self.call(**arguments)
        new(**arguments).call
      end

      def initialize(user:, account:, key:, action:, expected_version:, evidence_digest:, attributes: {}, template_token: nil)
        @user, @account, @key, @action = user, account, key, action.to_s
        @expected_version = Integer(expected_version.to_s, exception: false)
        @evidence_digest = evidence_digest.to_s
        @attributes = attributes.to_h
        @template_token = template_token.to_s
      end

      def call
        Access.authorize!(user: user, account: account)
        raise Invalid, "Choose a valid candidate action." unless action.in?(%w[create link ignore reopen])
        raise Invalid, "Refresh this candidate before saving." unless expected_version

        result = account.with_lock do
          candidate = Query.new(account: account).find!(key)
          decision = candidate[:decision] || account.recurring_candidate_decisions.new(
            user: user, budget_workspace: account.budget_workspace, merchant_key: key
          )
          next decision if decision.persisted? && decision.request_digest == request_digest
          current_version = decision.persisted? ? decision.lock_version : -1
          raise Invalid, "This candidate was already reviewed. Refresh it before changing the decision." unless current_version == expected_version

          if action == "reopen"
            decision.assign_attributes(status: "unreviewed", subscription: nil, monthly_bill: nil)
          else
            raise Invalid, "Restore this candidate to review before changing its decision." unless decision.status_unreviewed?
            unless candidate[:evidence_available] && candidate[:evidence_digest] == evidence_digest
              raise Invalid, "The supporting activity changed. Review the refreshed evidence and save again."
            end
            apply_resolution(decision)
          end
          decision.assign_attributes(evidence_summary: Query.summary(candidate), reviewed_at: Time.current, request_digest: request_digest)
          decision.save!
          decision
        end
        ActiveSupport::Notifications.instrument("recurring_candidate.resolved", action: action, status: result.status)
        result
      ensure
        account.recurring_candidate_decisions.reset
        user.subscriptions.reset
        user.monthly_bills.reset
      end

      private

      attr_reader :user, :account, :key, :action, :expected_version, :evidence_digest, :attributes, :template_token

      def request_digest
        @request_digest ||= Digest::SHA256.hexdigest(Platform::CanonicalJson.dump(
          action: action, version: expected_version, evidence: evidence_digest, attributes: attributes, template: template_token
        ))
      end

      def apply_resolution(decision)
        if action == "ignore"
          decision.status = "ignored"
        else
          template = action == "create" ? create_template : existing_template
          unless template.budget_workspace_id == account.budget_workspace_id
            raise Invalid, "Choose a recurring transaction in this account's workspace."
          end
          decision.assign_attributes(status: "linked", subscription: template.is_a?(Subscription) ? template : nil, monthly_bill: template.is_a?(MonthlyBill) ? template : nil)
        end
      end

      def create_template
        form = TemplateForm.new(attributes)
        raise Invalid, form.errors.full_messages.to_sentence unless form.valid?
        collection = form.template_kind == "subscription" ? user.subscriptions : user.monthly_bills
        values = form.template_attributes(user: user)
        linked_account = values[:linked_account]
        if linked_account && (linked_account.budget_workspace_id != account.budget_workspace_id || linked_account.currency_code != account.currency_code)
          raise Invalid, "Choose an activity account in the same workspace and currency."
        end
        template = Planning::LegacyTemplateWriter.create(scope: collection, attributes: values)
        raise Invalid, template.errors.full_messages.to_sentence unless template.persisted? && template.errors.none?
        template
      end

      def existing_template
        type, id = template_token.split(":", 2)
        scope = { "subscription" => user.subscriptions, "monthly_bill" => user.monthly_bills }[type]
        raise Invalid, "Choose a subscription or bill to link." unless scope && id.present?
        scope.find(id)
      end
    end
  end
end
