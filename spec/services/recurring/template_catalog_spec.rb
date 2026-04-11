require "rails_helper"

RSpec.describe Recurring::TemplateCatalog do
  describe ".recurring_source_files" do
    it "returns the recurring template source_file values" do
      expect(described_class.recurring_source_files).to eq(%w[pay_schedule subscription monthly_bill payment_plan])
    end
  end

  describe ".definition_for_source_file" do
    it "returns metadata for credit card estimates" do
      definition = described_class.definition_for_source_file("credit_card_estimate")

      expect(definition.fetch(:model_name)).to eq("CreditCard")
      expect(definition.fetch(:param_key)).to eq(:credit_card)
    end
  end

  describe ".definition_for" do
    it "resolves metadata from model instances" do
      record = build(:subscription)
      definition = described_class.definition_for(record)

      expect(definition.fetch(:source_file)).to eq("subscription")
    end
  end

  describe ".wizard_template_types" do
    it "returns the template types exposed in the wizard" do
      expect(described_class.wizard_template_types).to eq(%w[pay_schedule subscription monthly_bill payment_plan])
    end
  end
end
