module Identity
  class PersonalWorkspaceProvisioner
    Result = Data.define(:workspace, :membership)

    def self.call(user:)
      new(user: user).call
    end

    def initialize(user:)
      @user = user
    end

    def call
      ApplicationRecord.transaction do
        workspace = BudgetWorkspace.find_or_create_by!(legacy_owner_user: user) do |record|
          record.name = "My budget"
          record.default_currency_code = Platform::TargetBackfill::WorkspaceBootstrap::DEFAULT_CURRENCY
          record.status = "active"
        end
        membership = WorkspaceMembership.find_or_create_by!(budget_workspace: workspace, user: user) do |record|
          record.role = "owner"
          record.status = "active"
          record.joined_at = Time.current
        end

        Result.new(workspace: workspace, membership: membership)
      end
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    private

    attr_reader :user
  end
end
