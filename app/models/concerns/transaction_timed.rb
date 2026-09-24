module TransactionTimed
  extend ActiveSupport::Concern

  included do
    class_attribute :timing_date_column, :timing_timestamp_column, :timing_income_method
    before_validation :apply_transaction_time
    validate :validate_transaction_time
  end

  def transaction_time=(value)
    @submitted_transaction_time = value.to_s
  end

  def transaction_time
    return @submitted_transaction_time if defined?(@submitted_transaction_time)

    public_send(timing_timestamp_column)&.in_time_zone(timing_zone_name)&.strftime("%H:%M:%S")
  end

  def timing_zone_name
    return timing_time_zone if timing_time_zone.present?

    workspace = budget_workspace if budget_workspace_id.present? || association(:budget_workspace).loaded?
    workspace&.time_zone || (respond_to?(:budget_month) && budget_month&.budget_workspace&.time_zone) || "UTC"
  end

  def chronological_key(incoming: public_send(timing_income_method))
    Accounts::TransactionTiming.key(date: public_send(timing_date_column), incoming: incoming,
      timestamp: public_send(timing_timestamp_column), zone_name: timing_zone_name, created_at: created_at, id: id)
  end

  private

  def apply_transaction_time
    self.timing_time_zone = ActiveSupport::TimeZone[timing_time_zone]&.tzinfo&.identifier || timing_time_zone if timing_time_zone.present?
    @transaction_time_error = nil
    explicit_submission = defined?(@submitted_transaction_time)
    changed_date = will_save_change_to_attribute?(timing_date_column)
    return unless explicit_submission || (changed_date && public_send(timing_timestamp_column).present? && !will_save_change_to_attribute?(timing_timestamp_column))

    clock = explicit_submission ? @submitted_transaction_time : transaction_time
    self[timing_timestamp_column] = if clock.blank?
      nil
    else
      self.timing_time_zone = Accounts::TransactionTiming.zone(nil, name: timing_zone_name).tzinfo.identifier
      Accounts::TransactionTiming.parse(date: public_send(timing_date_column), clock: clock, zone_name: timing_time_zone)
    end
  rescue ArgumentError => error
    @transaction_time_error = error.message
  end

  def validate_transaction_time
    errors.add(:transaction_time, @transaction_time_error) if @transaction_time_error
    if timing_time_zone.present? && ActiveSupport::TimeZone[timing_time_zone].nil?
      errors.add(:timing_time_zone, "is not a valid timezone")
    end
  end
end
