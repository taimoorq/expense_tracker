class HelpController < ApplicationController
  def show
    @releases = ReleaseCatalog.releases
    @latest_release = @releases.first
    @latest_unread_release = current_user.latest_unread_release
  end

  def acknowledge_release_notes
    release = ReleaseCatalog.find(params[:version])

    if release.present? && current_user.update(last_seen_release_version: release.version)
      redirect_back fallback_location: help_path(anchor: "whats-new"), notice: "#{release.label} marked as read."
    else
      redirect_back fallback_location: help_path(anchor: "whats-new"), alert: "We could not update your release-note status."
    end
  end
end
