module Accounts
  class TargetBalanceResolver
    def initialize(account:, as_of: Date.current)
      @account = account
      @as_of = as_of
    end

    def call
      Accounts::TargetBalanceBatch.call(accounts: [ account ], as_of: as_of).fetch(account)
    end

    private

    attr_reader :account, :as_of
  end
end
