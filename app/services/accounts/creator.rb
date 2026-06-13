module Accounts
  class Creator
    Result = Data.define(:account, :initial_snapshot, :credit_card_payment_schedule, :success?, :notice)

    def self.call(user:, account_params:, initial_snapshot_params:, credit_card_payment_schedule_params:)
      new(
        user: user,
        account_params: account_params,
        initial_snapshot_params: initial_snapshot_params,
        credit_card_payment_schedule_params: credit_card_payment_schedule_params
      ).call
    end

    def initialize(user:, account_params:, initial_snapshot_params:, credit_card_payment_schedule_params:)
      @user = user
      @account_params = account_params
      @initial_snapshot_params = initial_snapshot_params
      @credit_card_payment_schedule_params = credit_card_payment_schedule_params
    end

    def call
      account = user.accounts.new(account_params)
      initial_snapshot = build_initial_snapshot(account)
      credit_card_payment_schedule = build_credit_card_payment_schedule(account)

      unless valid_records?(account, initial_snapshot, credit_card_payment_schedule)
        return Result.new(
          account: account,
          initial_snapshot: initial_snapshot,
          credit_card_payment_schedule: credit_card_payment_schedule,
          success?: false,
          notice: nil
        )
      end

      ApplicationRecord.transaction do
        account.save!
        initial_snapshot&.save!
        credit_card_payment_schedule&.save!
      end

      Result.new(
        account: account,
        initial_snapshot: initial_snapshot,
        credit_card_payment_schedule: credit_card_payment_schedule,
        success?: true,
        notice: success_notice(initial_snapshot, credit_card_payment_schedule)
      )
    end

    private

    attr_reader :user, :account_params, :initial_snapshot_params, :credit_card_payment_schedule_params

    def build_initial_snapshot(account)
      return nil unless initial_snapshot_requested?

      account.account_snapshots.new(initial_snapshot_params)
    end

    def initial_snapshot_requested?
      snapshot_values = initial_snapshot_params.to_h.with_indifferent_access

      snapshot_values[:balance].present? ||
        snapshot_values[:available_balance].present? ||
        snapshot_values[:notes].present?
    end

    def build_credit_card_payment_schedule(account)
      return nil unless credit_card_payment_schedule_requested?(account)

      payment_account = user.accounts.find_by(id: credit_card_payment_schedule_params[:payment_account_id])

      user.credit_cards.new(
        name: account.name,
        linked_account: account,
        payment_account_id: credit_card_payment_schedule_params[:payment_account_id],
        account: payment_account&.name,
        minimum_payment: credit_card_payment_schedule_params[:minimum_payment],
        due_day: credit_card_payment_schedule_params[:due_day],
        priority: credit_card_payment_schedule_params[:priority],
        active: credit_card_payment_schedule_params.fetch(:active, true),
        notes: credit_card_payment_schedule_params[:notes]
      )
    end

    def credit_card_payment_schedule_requested?(account)
      account.credit_card? && ActiveModel::Type::Boolean.new.cast(credit_card_payment_schedule_params[:enabled])
    end

    def valid_records?(account, initial_snapshot, credit_card_payment_schedule)
      account.valid? &&
        (initial_snapshot.nil? || initial_snapshot.valid?) &&
        (credit_card_payment_schedule.nil? || credit_card_payment_schedule.valid?)
    end

    def success_notice(initial_snapshot, credit_card_payment_schedule)
      if initial_snapshot.present? && credit_card_payment_schedule.present?
        "Account created, initial balance recorded, and card payment scheduled."
      elsif credit_card_payment_schedule.present?
        "Account created and card payment scheduled. Add a balance snapshot when you are ready."
      elsif initial_snapshot.present?
        "Account created and initial balance recorded."
      else
        "Account created. Add a balance snapshot to start tracking it."
      end
    end
  end
end
