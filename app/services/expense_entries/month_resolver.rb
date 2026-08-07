module ExpenseEntries
  class MonthResolver
    Result = Data.define(:budget_month, :error_message) do
      def success?
        error_message.blank?
      end
    end

    def self.call(user:, current_month:, occurred_on:, allow_move:)
      new(user: user, current_month: current_month, occurred_on: occurred_on, allow_move: allow_move).call
    end

    def initialize(user:, current_month:, occurred_on:, allow_move:)
      @user = user
      @current_month = current_month
      @occurred_on = occurred_on
      @allow_move = allow_move
    end

    def call
      parsed_date = parse_date
      return Result.new(budget_month: current_month, error_message: nil) if occurred_on.blank?
      return Result.new(budget_month: current_month, error_message: "is not a valid date") if parsed_date.blank?

      target_month_on = parsed_date.beginning_of_month
      return Result.new(budget_month: current_month, error_message: nil) if target_month_on == current_month_on

      target_month = user.budget_months.find_by(month_on: target_month_on)
      return Result.new(budget_month: target_month, error_message: nil) if allow_move && target_month.present?

      Result.new(
        budget_month: current_month,
        error_message: allow_move ? missing_month_message(target_month_on) : selected_month_message
      )
    end

    private

    attr_reader :user, :current_month, :occurred_on, :allow_move

    def parse_date
      return occurred_on if occurred_on.is_a?(Date)

      Date.iso8601(occurred_on.to_s)
    rescue ArgumentError
      nil
    end

    def current_month_on
      @current_month_on ||= current_month.month_on.to_date.beginning_of_month
    end

    def current_range
      "#{current_month_on.strftime('%B %-d')} through #{current_month_on.end_of_month.strftime('%B %-d')}"
    end

    def selected_month_message
      "must be in #{current_month.label} (#{current_range})"
    end

    def missing_month_message(target_month_on)
      target_label = target_month_on.strftime("%B %Y")
      "is outside #{current_month.label}. Create #{target_label} first, or choose a date from #{current_range}."
    end
  end
end
