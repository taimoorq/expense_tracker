class EntryWizardTemplateCreator
  TEMPLATE_TYPES = TemplateTypeRegistry.wizard_template_types.freeze

  attr_reader :template_record

  def initialize(user:, expense_entry:, params:)
    @user = user
    @expense_entry = expense_entry
    @params = params.to_h.with_indifferent_access
    @template_record = nil
    @error_messages = []
  end

  def requested?
    ActiveModel::Type::Boolean.new.cast(@params[:enabled])
  end

  def save
    return true unless requested?

    @template_record = build_template_record
    return false if @template_record.nil?

    @template_record.save
  end

  def error_messages
    return @error_messages if @error_messages.any?
    return [] if @template_record.nil?

    @template_record.errors.full_messages.map { |message| "Recurring: #{message}" }
  end

  private

  def build_template_record
    template_type = @params[:template_type].presence

    unless TEMPLATE_TYPES.include?(template_type)
      @error_messages = [ "Recurring: choose a valid recurring transaction type." ]
      return nil
    end

    unless TemplateTypeRegistry.wizard_sections_for(template_type).include?(@expense_entry.section)
      @error_messages = [ "Recurring: #{template_type.humanize} is not available for #{@expense_entry.section.humanize.downcase} entries." ]
      return nil
    end

    case template_type
    when "pay_schedule"
      build_pay_schedule
    when "subscription"
      build_subscription
    when "monthly_bill"
      build_monthly_bill
    when "payment_plan"
      build_payment_plan
    end
  end

  def build_pay_schedule
    @user.pay_schedules.new(
      name: @expense_entry.payee,
      cadence: @params[:cadence].presence || "monthly",
      amount: effective_amount,
      first_pay_on: @expense_entry.occurred_on,
      day_of_month_one: @params[:day_of_month_one].presence || @expense_entry.occurred_on&.day,
      day_of_month_two: @params[:day_of_month_two].presence,
      weekend_adjustment: @params[:weekend_adjustment].presence || "no_adjustment",
      account: @expense_entry.account,
      active: true
    )
  end

  def build_subscription
    @user.subscriptions.new(
      name: @expense_entry.payee,
      amount: effective_amount,
      due_day: due_day,
      account: @expense_entry.account,
      active: true,
      notes: @expense_entry.notes
    )
  end

  def build_monthly_bill
    @user.monthly_bills.new(
      name: @expense_entry.payee,
      kind: @params[:kind].presence || "fixed_payment",
      default_amount: effective_amount,
      due_day: due_day,
      billing_frequency: @params[:billing_frequency].presence || "monthly",
      billing_months: billing_months,
      account: @expense_entry.account,
      active: true,
      notes: @expense_entry.notes
    )
  end

  def build_payment_plan
    @user.payment_plans.new(
      name: @expense_entry.payee,
      total_due: @params[:total_due],
      amount_paid: @params[:amount_paid].presence || 0,
      monthly_target: effective_amount,
      due_day: due_day,
      account: @expense_entry.account,
      active: true,
      notes: @expense_entry.notes
    )
  end

  def due_day
    @params[:due_day].presence || @expense_entry.occurred_on&.day
  end

  def effective_amount
    @expense_entry.planned_amount.presence || @expense_entry.actual_amount.presence
  end

  def billing_months
    months = Array(@params[:billing_months]).reject(&:blank?).map(&:to_i)
    return months if months.any?

    frequency = @params[:billing_frequency].presence || "monthly"
    MonthlyBill::BILLING_MONTHS_BY_FREQUENCY.fetch(frequency, [ (@expense_entry.occurred_on || Date.current).month ])
  end
end
