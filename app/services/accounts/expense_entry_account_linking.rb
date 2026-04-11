module Accounts
  class ExpenseEntryAccountLinking
    class << self
      def relink_for(user)
        Budgeting::ExpenseEntryProvenanceRepair.relink_for(user)
      end
    end
  end
end
