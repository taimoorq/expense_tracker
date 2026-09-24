module BankConnections
  module Access
    module_function

    def authorize!(workspace:, membership:)
      Identity::WorkspaceAccess.authorize_write!(workspace: workspace, membership: membership)
      unless membership.role_owner? && !membership.user.access_state_suspended?
        raise Identity::WorkspaceAccess::NotAuthorized, "Only the active workspace owner can manage bank connections."
      end
    end
  end
end
