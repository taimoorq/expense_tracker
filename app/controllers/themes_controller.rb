class ThemesController < ApplicationController
  def update
    theme = ThemePalette.fetch(params[:theme])

    cookies.signed.permanent[ThemePalette::COOKIE_KEY] = {
      value: theme.key,
      httponly: true,
      secure: Rails.application.config.force_ssl,
      same_site: :lax
    }

    redirect_back fallback_location: root_path
  end
end
