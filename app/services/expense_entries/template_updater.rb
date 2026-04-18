module ExpenseEntries
  class TemplateUpdater
    Result = Data.define(:template_record, :success?, :missing?)

    def self.call(user:, entry:, params:)
      new(user: user, entry: entry, params: params).call
    end

    def initialize(user:, entry:, params:)
      @user = user
      @entry = entry
      @params = params
    end

    def call
      template_record = ExpenseEntries::TemplateLookup.call(user: user, entry: entry)
      return Result.new(template_record: nil, success?: false, missing?: true) unless template_record

      success = template_record.update(template_params_for(template_record))
      Result.new(template_record: template_record, success?: success, missing?: false)
    end

    private

    attr_reader :user, :entry, :params

    def template_params_for(record)
      return {} unless record.class.respond_to?(:template_param_key)

      params.require(record.class.template_param_key).permit(*record.class.template_permitted_attributes)
    end
  end
end
