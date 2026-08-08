module Platform
  module TargetTranslation
    class PlanningTemplate
      def self.attributes(source:, workspace:, archived_at: nil)
        {
          budget_workspace: workspace,
          name: source.name,
          currency_code: workspace.default_currency_code,
          archived_at: archived_at || (source.active? ? nil : source.updated_at),
          notes: source.try(:notes)
        }.merge(type_attributes(source))
      end

      def self.type_attributes(source)
        case source
        when PaySchedule
          values("paycheck", "income", "other", source.amount, source.linked_account, nil, source.first_pay_on, source.ends_on)
        when Subscription
          values("subscription", "outflow", "fixed", source.amount, source.linked_account)
        when MonthlyBill
          group = source.fixed_payment? ? "fixed" : "variable"
          values("bill", "outflow", group, source.default_amount || 0, source.linked_account)
        when PaymentPlan
          values("payment_plan", "outflow", "debt", source.monthly_amount, source.linked_account)
        when CreditCard
          values(
            "credit_card_payment",
            "outflow",
            "debt",
            source.minimum_payment,
            source.payment_account,
            source.linked_account
          )
        else
          raise ArgumentError, "Unsupported planning source #{source.class.name}"
        end
      end

      def self.recurrence_attributes(source)
        case source
        when PaySchedule
          pay_schedule_recurrence_attributes(source)
        when Subscription, PaymentPlan
          monthly_recurrence_attributes(source.due_day)
        when MonthlyBill
          monthly_recurrence_attributes(source.due_day).merge(cadence: "custom_months")
        else
          raise ArgumentError, "#{source.class.name} does not use a recurrence rule"
        end
      end

      def self.allowed_months(source)
        source.is_a?(MonthlyBill) ? source.billing_months : []
      end

      def self.payment_plan_term_attributes(source)
        {
          total_due: source.total_due,
          opening_paid_adjustment: source.amount_paid,
          monthly_target: source.monthly_target || 0
        }
      end

      def self.credit_card_policy_attributes(source, workspace:)
        {
          budget_workspace: workspace,
          liability_account: source.linked_account,
          payment_account: source.payment_account,
          minimum_payment: source.minimum_payment,
          due_day: source.due_day,
          priority: source.priority,
          estimate_policy: "minimum"
        }
      end

      def self.values(kind, flow_kind, budget_group, amount, source_account, destination_account = nil, active_from = nil, active_until = nil)
        {
          kind: kind,
          flow_kind: flow_kind,
          budget_group: budget_group,
          default_amount: amount || 0,
          source_account: source_account,
          destination_account: destination_account,
          active_from: active_from,
          active_until: active_until
        }
      end
      private_class_method :values

      def self.pay_schedule_recurrence_attributes(source)
        cadence, interval_count = source.biweekly? ? [ "weekly", 2 ] : [ source.weekly? ? "weekly" : "monthly", 1 ]
        {
          cadence: cadence,
          interval_count: interval_count,
          anchor_on: source.first_pay_on,
          day_one: source.day_of_month_one,
          day_two: source.semimonthly? ? source.day_of_month_two : nil,
          weekend_policy: source.no_adjustment? ? "none" : source.weekend_adjustment,
          starts_on: source.first_pay_on,
          ends_on: source.ends_on
        }
      end
      private_class_method :pay_schedule_recurrence_attributes

      def self.monthly_recurrence_attributes(due_day)
        {
          cadence: "monthly",
          interval_count: 1,
          anchor_on: Date.new(2000, 1, due_day),
          day_one: due_day,
          weekend_policy: "none",
          starts_on: Date.new(1970, 1, 1)
        }
      end
      private_class_method :monthly_recurrence_attributes
    end
  end
end
