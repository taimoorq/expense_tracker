module Identity
  module WorkspaceAccess
    module_function

    def authorize_write!(workspace:, membership:)
      unless workspace.status_active? && membership&.budget_workspace_id == workspace.id && membership.status_active?
        raise NotAuthorized, "An active membership in this workspace is required"
      end
      raise NotAuthorized, "Viewer memberships cannot change financial data" if membership.role_viewer?

      true
    end

    class NotAuthorized < StandardError; end
  end
end
