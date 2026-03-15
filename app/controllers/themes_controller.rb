class ThemesController < ApplicationController
  def update
    theme = ThemePalette.fetch(params[:theme])

    cookies.signed.permanent[ThemePalette::COOKIE_KEY] = {
      value: theme.key,
      httponly: true,
      same_site: :lax
    }

    redirect_back fallback_location: root_path
  end
end
