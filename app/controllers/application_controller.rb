class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  layout :determine_layout

  before_action :authenticate_user!, unless: :devise_controller?

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  protected

  def after_sign_out_path_for(_resource_or_scope)
    new_user_session_path
  end

  def determine_layout
    devise_controller? ? "authentication" : "application"
  end
end
