require "rails_helper"

RSpec.describe "Planning template CRUD", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  shared_examples "planning template resource" do |collection_name:, factory:, create_path_helper:, destroy_path_helper:, param_key:, valid_params:, update_params:, create_notice:, update_notice:, destroy_notice:|
    it "creates #{collection_name.tr('_', ' ')} records" do
      params = valid_params.respond_to?(:call) ? instance_exec(&valid_params) : valid_params

      expect do
        post public_send(create_path_helper), params: { param_key => params }
      end.to change { user.public_send(collection_name).count }.by(1)

      expect(response).to redirect_to(planning_templates_path)
      expect(flash[:notice]).to eq(create_notice)
    end

    it "destroys #{collection_name.tr('_', ' ')} records" do
      record = create(factory, user: user)

      expect do
        delete public_send(destroy_path_helper, record)
      end.to change { user.public_send(collection_name).count }.by(-1)

      expect(response).to redirect_to(planning_templates_path)
      expect(flash[:notice]).to eq(destroy_notice)
    end

    it "supports turbo stream creation from the planning templates page" do
      params = valid_params.respond_to?(:call) ? instance_exec(&valid_params) : valid_params

      expect do
        post public_send(create_path_helper),
          params: { param_key => params, return_to: planning_templates_path },
          headers: { "ACCEPT" => Mime[:turbo_stream].to_s }
      end.to change { user.public_send(collection_name).count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    end

    it "updates #{collection_name.tr('_', ' ')} records" do
      record = create(factory, user: user)
      params = update_params.respond_to?(:call) ? instance_exec(record, &update_params) : update_params

      patch public_send(destroy_path_helper, record), params: { param_key => params, return_to: planning_templates_path }

      expect(response).to redirect_to(planning_templates_path)
      expect(flash[:notice]).to eq(update_notice)

      params.each do |attribute, value|
        actual_value = record.reload.public_send(attribute)

        if actual_value.is_a?(BigDecimal)
          expect(actual_value).to eq(value.to_d)
        else
          expect(actual_value.to_s).to eq(value.to_s)
        end
      end
    end
  end

  include_examples "planning template resource",
    collection_name: "pay_schedules",
    factory: :pay_schedule,
    create_path_helper: :pay_schedules_path,
    destroy_path_helper: :pay_schedule_path,
    param_key: :pay_schedule,
    valid_params: -> {
      {
        name: "Acme Payroll",
        cadence: "monthly",
        amount: "2500.00",
        first_pay_on: "2026-01-15",
        day_of_month_one: 15,
        account: "Checking",
        active: true
      }
    },
    update_params: ->(_record) {
      {
        name: "Updated Payroll",
        account: "Savings",
        day_of_month_two: 25
      }
    },
    create_notice: "Pay schedule saved.",
    update_notice: "Pay schedule updated.",
    destroy_notice: "Pay schedule removed."

  include_examples "planning template resource",
    collection_name: "subscriptions",
    factory: :subscription,
    create_path_helper: :subscriptions_path,
    destroy_path_helper: :subscription_path,
    param_key: :subscription,
    valid_params: {
      name: "Netflix",
      amount: "19.99",
      due_day: 8,
      account: "Checking",
      active: true,
      notes: "Streaming"
    },
    update_params: {
      name: "Google Fi",
      amount: "97.74",
      due_day: 1,
      account: "Barclay Card US"
    },
    create_notice: "Subscription saved.",
    update_notice: "Subscription updated.",
    destroy_notice: "Subscription removed."

  include_examples "planning template resource",
    collection_name: "monthly_bills",
    factory: :monthly_bill,
    create_path_helper: :monthly_bills_path,
    destroy_path_helper: :monthly_bill_path,
    param_key: :monthly_bill,
    valid_params: {
      name: "Electric",
      kind: "fixed_payment",
      default_amount: "110.00",
      due_day: 12,
      account: "Checking",
      active: true,
      notes: "Utility"
    },
    update_params: {
      name: "Water Bill",
      default_amount: "125.50",
      due_day: 14,
      account: "Checking"
    },
    create_notice: "Monthly bill template saved.",
    update_notice: "Monthly bill template updated.",
    destroy_notice: "Monthly bill template removed."

  include_examples "planning template resource",
    collection_name: "payment_plans",
    factory: :payment_plan,
    create_path_helper: :payment_plans_path,
    destroy_path_helper: :payment_plan_path,
    param_key: :payment_plan,
    valid_params: {
      name: "Tax Plan",
      total_due: "1200.00",
      amount_paid: "200.00",
      monthly_target: "100.00",
      due_day: 18,
      account: "Checking",
      active: true,
      notes: "Installment"
    },
    update_params: {
      name: "IRS Plan",
      monthly_target: "150.00",
      due_day: 20,
      account: "Savings"
    },
    create_notice: "Payment plan saved.",
    update_notice: "Payment plan updated.",
    destroy_notice: "Payment plan removed."

  include_examples "planning template resource",
    collection_name: "credit_cards",
    factory: :credit_card,
    create_path_helper: :credit_cards_path,
    destroy_path_helper: :credit_card_path,
    param_key: :credit_card,
    valid_params: {
      name: "Visa",
      minimum_payment: "45.00",
      priority: 1,
      account: "Checking",
      active: true,
      notes: "Main card"
    },
    update_params: {
      name: "Barclays Visa",
      minimum_payment: "55.00",
      priority: 2,
      account: "Checking"
    },
    create_notice: "Credit card saved.",
    update_notice: "Credit card updated.",
    destroy_notice: "Credit card removed."
end
