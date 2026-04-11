class HelpController < ApplicationController
  def show
  end

  def releases
    @releases = Platform::ReleaseCatalog.releases
    @latest_release = @releases.first
    @latest_unread_release = current_user.latest_unread_release
  end

  def acknowledge_release_notes
    release = Platform::ReleaseCatalog.find(params[:version])

    if release.present? && current_user.update(last_seen_release_version: release.version)
      redirect_back fallback_location: help_releases_path, notice: "#{release.label} marked as read."
    else
      redirect_back fallback_location: help_releases_path, alert: "We could not update your release-note status."
    end
  end
end
