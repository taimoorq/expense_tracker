module Admin
  class BaseController < ApplicationController
    skip_before_action :authenticate_user!
    before_action :authenticate_admin_user!
    after_action :record_admin_audit_log

    layout "admin"

    private

    def set_admin_audit_context(action: nil, target_user: nil, metadata: {})
      @admin_audit_action = action if action.present?
      @admin_audit_target_user = target_user if target_user
      @admin_audit_metadata = metadata if metadata.present?
    end

    def record_admin_audit_log
      return unless current_admin_user
      return unless response.successful? || response.redirect?

      AdminAuditLog.create!(
        admin_user: current_admin_user,
        target_user: @admin_audit_target_user,
        action: @admin_audit_action || default_admin_audit_action,
        metadata: default_admin_audit_metadata.merge(@admin_audit_metadata || {}),
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
    end

    def default_admin_audit_action
      "#{controller_path}.#{action_name}"
    end

    def default_admin_audit_metadata
      {
        request_method: request.request_method,
        path: request.fullpath
      }
    end
  end
end
