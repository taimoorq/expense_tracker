class ThemesController < ApplicationController
  def update
    theme = Platform::ThemePalette.fetch(params[:theme])

    cookies.signed.permanent[Platform::ThemePalette::COOKIE_KEY] = {
      value: theme.key,
      httponly: true,
      secure: Rails.application.config.force_ssl,
      same_site: :lax
    }

    redirect_back fallback_location: root_path
  end
end
