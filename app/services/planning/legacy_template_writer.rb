module Planning
  class LegacyTemplateWriter
    def self.create(scope:, attributes:)
      resource = scope.new(attributes)
      persist(resource) { resource.save }
      resource
    end

    def self.update(resource:, attributes:)
      persist(resource) { resource.update(attributes) }
    end

    def self.destroy(resource:)
      ApplicationRecord.transaction do
        Platform::TargetSync::PlanningTemplateWriter.call(source: resource, action: :archive)
        resource.destroy!
      end
      true
    rescue Platform::TargetSync::WriteRejected => error
      resource.errors.add(:base, error.message)
      false
    end

    def self.persist(resource)
      saved = false
      ApplicationRecord.transaction do
        saved = yield
        Platform::TargetSync::PlanningTemplateWriter.call(source: resource) if saved
      end
      saved
    rescue Platform::TargetSync::WriteRejected => error
      resource.errors.add(:base, error.message)
      false
    end

    private_class_method :persist
  end
end
