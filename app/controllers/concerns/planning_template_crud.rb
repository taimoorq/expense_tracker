module PlanningTemplateCrud
  extend ActiveSupport::Concern

  included do
    before_action :set_budget_month
  end

  def create
    resource = resource_scope.new(resource_params)
    assign_resource(resource)

    if resource.save
      assign_resource(resource_scope.new)
      assign_collection(ordered_resources)
      respond_success(create_success_message)
    else
      assign_collection(ordered_resources)
      respond_error(resource.errors.full_messages.join(", "))
    end
  end

  def destroy
    resource_scope.find(params[:id]).destroy
    assign_resource(resource_scope.new)
    assign_collection(ordered_resources)
    respond_success(destroy_success_message)
  end

  private

  def set_budget_month
    @budget_month = current_user.budget_months.find_by(id: params[:budget_month_id])
  end

  def redirect_target
    params[:return_to].presence || @budget_month || planning_templates_path
  end

  def respond_success(message)
    respond_with_section_update(message:, flash_key: :notice)
  end

  def respond_error(message)
    respond_with_section_update(message:, flash_key: :alert, status: :unprocessable_entity)
  end

  def respond_with_section_update(message:, flash_key:, status: :ok)
    respond_to do |format|
      format.turbo_stream do
        flash.now[flash_key] = message
        render turbo_stream: [
          turbo_stream.replace("flash", partial: "shared/flash"),
          turbo_stream.replace(section_dom_id, partial: section_partial, locals: section_locals)
        ], status: status
      end
      format.html do
        redirect_options = flash_key == :notice ? { notice: message } : { alert: message }
        redirect_to redirect_target, redirect_options
      end
    end
  end

  def assign_resource(resource)
    instance_variable_set("@#{resource_name}", resource)
  end

  def assign_collection(records)
    instance_variable_set("@#{collection_name}", records)
  end

  def ordered_resources
    resource_scope.order(*resource_order)
  end

  def section_locals
    {
      budget_month: @budget_month,
      collection_name.to_sym => instance_variable_get("@#{collection_name}"),
      resource_name.to_sym => instance_variable_get("@#{resource_name}")
    }
  end

  def resource_scope
    current_user.public_send(collection_name)
  end

  def resource_params
    params.require(resource_name.to_sym).permit(*permitted_attributes)
  end

  def collection_name
    resource_name.pluralize
  end

  def section_partial
    "#{collection_name}/section"
  end

  def section_dom_id
    "#{collection_name}_section"
  end

  def resource_name
    raise NotImplementedError
  end

  def resource_order
    raise NotImplementedError
  end

  def permitted_attributes
    raise NotImplementedError
  end

  def create_success_message
    raise NotImplementedError
  end

  def destroy_success_message
    raise NotImplementedError
  end
end
