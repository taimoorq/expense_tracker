module Accounts
  class Updater
    def self.call(account:, attributes:)
      ApplicationRecord.transaction do
        return false unless account.update(attributes)

        Platform::TargetSync::AccountWriter.call(account: account)
      end
      true
    rescue Platform::TargetSync::WriteRejected => error
      account.errors.add(:base, error.message)
      false
    end
  end
end
