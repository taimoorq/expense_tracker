class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  layout :determine_layout

  before_action :authenticate_user!, unless: :devise_controller?
  before_action :enforce_current_user_access_state, unless: :devise_controller?

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  protected

  def after_sign_in_path_for(resource_or_scope)
    return admin_root_path if resource_or_scope.is_a?(AdminUser)

    super
  end

  def after_sign_out_path_for(_resource_or_scope)
    return new_admin_user_session_path if _resource_or_scope == :admin_user || _resource_or_scope.is_a?(AdminUser)

    new_user_session_path
  end

  def determine_layout
    devise_controller? ? "authentication" : "application"
  end

  def enforce_current_user_access_state
    return unless current_user&.access_state_suspended?

    sign_out(current_user)
    redirect_to new_user_session_path, alert: "Your access has been suspended. Contact an administrator for help."
  end
end
