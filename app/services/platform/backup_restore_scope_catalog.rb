module Platform
  class BackupRestoreScopeCatalog
    def initialize(user:)
      @user = user
    end

    def call
      {
        "planning_templates" => planning_template_scope,
        "budget_months" => budget_month_scope,
        "accounts" => account_scope
      }
    end

    private

    attr_reader :user

    def planning_template_scope
      {
        title: "Recurring Transactions",
        description: "Paycheck schedules, subscriptions, monthly bills, payment plans, and credit cards.",
        count: planning_template_counts.values.sum,
        detail: [
          "#{planning_template_counts[:pay_schedules]} pay schedules",
          "#{planning_template_counts[:subscriptions]} subscriptions",
          "#{planning_template_counts[:monthly_bills]} monthly bills",
          "#{planning_template_counts[:payment_plans]} payment plans",
          "#{planning_template_counts[:credit_cards]} credit cards"
        ].join(" • ")
      }
    end

    def budget_month_scope
      {
        title: "Months",
        description: "Budget months with nested entries, notes, and month-level amounts.",
        count: user.budget_months.count,
        detail: "#{user.expense_entries.count} entries across #{user.budget_months.count} months"
      }
    end

    def account_scope
      {
        title: "Accounts",
        description: "Accounts, balances, notes, and recorded snapshots.",
        count: user.accounts.count,
        detail: "#{user.account_snapshots.count} snapshots across #{user.accounts.count} accounts"
      }
    end

    def planning_template_counts
      @planning_template_counts ||= {
        pay_schedules: user.pay_schedules.count,
        subscriptions: user.subscriptions.count,
        monthly_bills: user.monthly_bills.count,
        payment_plans: user.payment_plans.count,
        credit_cards: user.credit_cards.count
      }
    end
  end
end
