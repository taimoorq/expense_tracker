module Accounts
  class TransactionBuilder
    def initialize(workspace:, attributes:)
      @workspace = workspace
      @attributes = attributes.to_h.symbolize_keys
    end

    def call
      amount = attributes.fetch(:amount).to_d
      raise ArgumentError, "amount must be positive" unless amount.positive?

      transaction = FinancialTransaction.create!(transaction_attributes(amount).merge(budget_workspace: workspace))
      posting_attributes(amount).each_with_index do |posting, sequence_number|
        transaction.account_postings.create!(
          posting.merge(
            budget_workspace: workspace,
            currency_code: workspace.default_currency_code,
            sequence_number: sequence_number
          )
        )
      end
      transaction
    end

    private

    attr_reader :attributes, :workspace

    def transaction_attributes(amount)
      {
        effective_on: attributes.fetch(:effective_on),
        posted_on: attributes[:posted_on],
        description: attributes.fetch(:description),
        payee: attributes[:payee],
        memo: attributes[:memo],
        category: attributes[:category],
        gross_amount: amount,
        currency_code: workspace.default_currency_code,
        flow_kind: flow_kind,
        state: attributes.fetch(:state, "posted"),
        origin_kind: attributes.fetch(:origin_kind, "manual"),
        idempotency_key: attributes[:idempotency_key]
      }
    end

    def posting_attributes(amount)
      case flow_kind
      when "income"
        [ posting(primary_account!, amount, "primary") ]
      when "outflow"
        [ posting(primary_account!, -amount, "primary") ]
      when "transfer"
        validate_transfer_accounts!
        [
          posting(attributes.fetch(:source_account), -amount, "source"),
          posting(attributes.fetch(:destination_account), amount, "destination")
        ]
      else
        raise ArgumentError, "unsupported flow kind #{flow_kind.inspect}"
      end
    end

    def posting(account, amount, role)
      validate_account!(account)
      { account: account, amount: amount, role: role }
    end

    def primary_account!
      attributes.fetch(:account)
    end

    def validate_transfer_accounts!
      source = attributes.fetch(:source_account)
      destination = attributes.fetch(:destination_account)
      raise ArgumentError, "transfer accounts must be different" if source.id == destination.id
    end

    def validate_account!(account)
      unless account.budget_workspace_id == workspace.id && account.currency_code == workspace.default_currency_code
        raise ArgumentError, "account must belong to the workspace and use its currency"
      end
    end

    def flow_kind
      @flow_kind ||= attributes.fetch(:flow_kind).to_s
    end
  end
end
