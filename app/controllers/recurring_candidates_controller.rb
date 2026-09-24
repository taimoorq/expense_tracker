class RecurringCandidatesController < ApplicationController
  before_action :set_account
  before_action :set_candidate, except: :index

  rescue_from Identity::WorkspaceAccess::NotAuthorized do |error|
    render plain: error.message, status: :forbidden
  end

  def index
    @filter = params[:status].presence_in(%w[unreviewed linked ignored]) || "unreviewed"
    candidates = Accounts::RecurringCandidates::Query.new(account: @account).call
    @counts = candidates.group_by { |candidate| candidate[:review_status] }.transform_values(&:size)
    selected = candidates.select { |candidate| candidate[:review_status] == @filter }
    @total = selected.size
    @page = params[:page].to_i.clamp(1, [ (@total / 12.0).ceil, 1 ].max)
    @candidates = selected.slice((@page - 1) * 12, 12) || []
  end

  def show
    prepare_review
  end

  def update
    decision = Accounts::RecurringCandidates::Resolve.call(
      user: current_user, account: @account, key: params[:id], action: params[:decision_action],
      expected_version: params[:expected_version], evidence_digest: params[:evidence_digest],
      attributes: template_params, template_token: params[:template_token]
    )
    @message = case decision.status
    when "linked" then "Recurring transaction saved. You can now add it to a month or review the next candidate."
    when "ignored" then "Candidate ignored. You can restore it from Ignored."
    else "Candidate restored to review."
    end
    redirect_to account_recurring_candidate_path(@account, params[:id]), notice: @message, status: :see_other
  rescue Accounts::RecurringCandidates::Resolve::Invalid, ActiveRecord::RecordInvalid, Platform::TargetSync::WriteRejected, Platform::TargetSync::Context::IncompleteBackfill => error
    @error = error.message
    set_candidate
    prepare_review
    render :show, status: :unprocessable_content
  end

  def month
    prepare_month
  rescue Recurring::AddTemplateToMonth::Invalid, Platform::TargetSync::Context::IncompleteBackfill => error
    @error = error.message
    render :month, status: :unprocessable_content
  end

  def add_to_month
    template = linked_template!
    month = current_user.budget_months.find(params[:budget_month_id])
    result = Recurring::AddTemplateToMonth.new(user: current_user, template: template, budget_month: month).call(expected_digest: params[:preview_digest])
    message = result.status == :added ? "Added to #{month.label} as planned." : "Already in #{month.label}; no duplicate was added."
    redirect_to month_account_recurring_candidate_path(@account, params[:id], budget_month_id: month.id), notice: message, status: :see_other
  rescue Recurring::AddTemplateToMonth::Invalid, Platform::TargetSync::WriteRejected, Platform::TargetSync::Context::IncompleteBackfill, ActiveRecord::RecordInvalid => error
    @error = "Your recurring transaction is saved. #{error.message}"
    prepare_month(preview: false)
    render :month, status: :unprocessable_content
  end

  private

  def set_account
    @account = current_user.accounts.find(params[:account_id])
    Accounts::RecurringCandidates::Access.authorize!(user: current_user, account: @account)
  end

  def set_candidate
    @candidate = Accounts::RecurringCandidates::Query.new(account: @account).find!(params[:id])
    @decision = @candidate[:decision]
  end

  def prepare_review
    defaults = {
      name: @candidate[:merchant], amount: @candidate[:estimated_amount], due_day: @candidate[:last_on]&.day,
      linked_account_id: @account.id
    }
    @form = Accounts::RecurringCandidates::TemplateForm.new(defaults.merge(template_params))
    @accounts = current_user.accounts.active_first.to_a
    @templates = (current_user.subscriptions.to_a + current_user.monthly_bills.to_a)
      .select { |template| template.budget_workspace_id == @account.budget_workspace_id }
      .sort_by { |template| [ Accounts::RecurringCandidates::Detector.key(template.name) == @candidate[:key] ? 0 : 1, template.name.downcase ] }
    @possible_matches = @templates.filter_map do |template|
      amount = template.is_a?(Subscription) ? template.amount : template.default_amount
      reason = if Accounts::RecurringCandidates::Detector.key(template.name) == @candidate[:key]
        "Matching merchant name"
      elsif template.linked_account_id == @account.id && amount.to_d == @candidate[:estimated_amount]
        "Same account and expected amount"
      end
      [ template, reason ] if reason
    end.first(3)
    @next_candidate = Accounts::RecurringCandidates::Query.new(account: @account).call.find do |candidate|
      candidate[:key] != @candidate[:key] && candidate[:review_status] == "unreviewed" && candidate[:evidence_available]
    end
  end

  def linked_template!
    raise ActiveRecord::RecordNotFound unless @decision&.status_linked? && @decision.template
    @decision.template
  end

  def prepare_month(preview: true)
    @template = linked_template!
    @months = current_user.budget_months.where(budget_workspace_id: @template.budget_workspace_id).recent_first.to_a
    periods = @account.budget_workspace&.budget_periods&.index_by(&:starts_on) || {}
    @months.select! do |month|
      period = periods[month.month_on]
      period ? period.state.in?(%w[open reopened]) : !@account.budget_workspace&.target_writes_enabled? && !@account.budget_workspace&.target_reads_enabled?
    end
    @month = if params[:budget_month_id].present?
      current_user.budget_months.find(params[:budget_month_id])
    else
      @months.find { |month| month.month_on == Date.current.beginning_of_month }
    end
    @preview = Recurring::AddTemplateToMonth.new(user: current_user, template: @template, budget_month: @month).preview if @month && preview
  end

  def template_params
    params.fetch(:candidate_template, ActionController::Parameters.new).permit(
      :template_kind, :name, :amount, :due_day, :linked_account_id, :active, :notes, :kind, :billing_frequency, billing_months: []
    ).to_h.symbolize_keys
  end
end
