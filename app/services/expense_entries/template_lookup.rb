module ExpenseEntries
  class TemplateLookup
    def self.call(user:, entry:)
      new(user: user, entry: entry).call
    end

    def initialize(user:, entry:)
      @user = user
      @entry = entry
    end

    def call
      linked_template = entry.source_template
      if linked_template.present? && linked_template.respond_to?(:user_id) && linked_template.user_id == user.id
        return linked_template
      end

      definition = entry.source_definition
      return nil if definition.blank?

      user.public_send(definition.fetch(:model_class).model_name.route_key).find_by(name: entry.payee)
    end

    private

    attr_reader :user, :entry
  end
end
