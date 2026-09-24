module Accounts
  module RecurringCandidates
    class TemplateForm
      include ActiveModel::Model
      include ActiveModel::Attributes

      attribute :template_kind, :string, default: "subscription"
      attribute :name, :string
      attribute :amount, :decimal
      attribute :due_day, :integer
      attribute :linked_account_id, :string
      attribute :active, :boolean, default: true
      attribute :notes, :string
      attribute :kind, :string, default: "fixed_payment"
      attribute :billing_frequency, :string, default: "monthly"
      attr_accessor :billing_months

      validates :template_kind, inclusion: { in: %w[subscription monthly_bill] }
      validates :name, presence: true
      validates :amount, numericality: { greater_than: 0 }
      validates :due_day, inclusion: { in: 1..31 }
      validates :kind, inclusion: { in: MonthlyBill.kinds.keys }
      validates :billing_frequency, inclusion: { in: MonthlyBill.billing_frequencies.keys }

      def template_attributes(user:)
        account = user.accounts.find(linked_account_id) if linked_account_id.present?
        values = { name: name, due_day: due_day, linked_account: account, account: account&.name, active: active, notes: notes }
        if template_kind == "subscription"
          values.merge(amount: amount)
        else
          values.merge(default_amount: amount, kind: kind, billing_frequency: billing_frequency, billing_months: billing_months)
        end
      end
    end
  end
end
