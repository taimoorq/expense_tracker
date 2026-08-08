module Accounts
  class SnapshotWriter
    def self.create(account:, attributes:)
      snapshot = account.account_snapshots.new(attributes)
      persist(snapshot) { snapshot.save }
      snapshot
    end

    def self.update(snapshot:, attributes:)
      persist(snapshot) { snapshot.update(attributes) }
    end

    def self.destroy(snapshot:)
      ApplicationRecord.transaction do
        Platform::TargetSync::AccountSnapshotWriter.call(snapshot: snapshot, action: :supersede)
        snapshot.destroy!
      end
      true
    rescue Platform::TargetSync::WriteRejected => error
      snapshot.errors.add(:base, error.message)
      false
    end

    def self.persist(snapshot)
      saved = false
      ApplicationRecord.transaction do
        saved = yield
        Platform::TargetSync::AccountSnapshotWriter.call(snapshot: snapshot) if saved
      end
      saved
    rescue Platform::TargetSync::WriteRejected => error
      snapshot.errors.add(:base, error.message)
      false
    end

    private_class_method :persist
  end
end
