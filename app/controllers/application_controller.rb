class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  layout :determine_layout

  before_action :authenticate_user!, unless: :devise_controller?
  before_action :enforce_current_user_access_state, unless: :devise_controller?
  before_action :set_current_theme

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :available_themes, :current_theme, :current_theme_class, :current_theme_css_variables, :current_theme_meta_color,
    :latest_release, :latest_unread_release, :unread_release_count

  protected

  def after_sign_in_path_for(resource_or_scope)
    return admin_root_path if resource_or_scope.is_a?(AdminUser)

    stored_location = stored_location_for(resource_or_scope)
    return stored_location if stored_location.present?

    return resource_or_scope.landing_page_path if resource_or_scope.is_a?(User)

    super
  end

  def after_sign_out_path_for(_resource_or_scope)
    return new_admin_user_session_path if _resource_or_scope == :admin_user || _resource_or_scope.is_a?(AdminUser)

    new_user_session_path
  end

  def determine_layout
    devise_controller? ? "authentication" : "application"
  end

  def available_themes
    Platform::ThemePalette.all
  end

  def current_theme
    @current_theme ||= Platform::ThemePalette.fetch(cookies.signed[Platform::ThemePalette::COOKIE_KEY])
  end

  def current_theme_class
    current_theme.css_class
  end

  def current_theme_css_variables
    current_theme.css_variables.map { |name, value| "#{name}: #{value}" }.join("; ")
  end

  def current_theme_meta_color
    current_theme.meta_color
  end

  def latest_release
    Platform::ReleaseCatalog.latest
  end

  def latest_unread_release
    return unless user_signed_in?

    current_user.latest_unread_release
  end

  def unread_release_count
    return 0 unless user_signed_in?

    current_user.unread_release_count
  end

  def enforce_current_user_access_state
    return unless current_user&.access_state_suspended?

    sign_out(current_user)
    redirect_to new_user_session_path, alert: "Your access has been suspended. Contact an administrator for help."
  end

  def set_current_theme
    @current_theme = Platform::ThemePalette.fetch(cookies.signed[Platform::ThemePalette::COOKIE_KEY])
  end
end
