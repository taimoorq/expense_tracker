module Admin
  class UsersController < BaseController
    before_action :load_user, only: [ :show, :suspend, :restore ]

    def index
      @users = User.order(:email)

      set_admin_audit_context(action: "admin.users.index")
    end

    def show
      set_admin_audit_context(action: "admin.users.show", target_user: @user)
    end

    def suspend
      transition_user_access!(to: :suspended, audit_action: "admin.users.suspend", notice: "User access suspended.")
    end

    def restore
      transition_user_access!(to: :active, audit_action: "admin.users.restore", notice: "User access restored.")
    end

    private

    def load_user
      @user = User.find(params[:id])
    end

    def transition_user_access!(to:, audit_action:, notice:)
      previous_state = @user.access_state

      if previous_state == to.to_s
        set_admin_audit_context(
          action: audit_action,
          target_user: @user,
          metadata: transition_audit_metadata(previous_state: previous_state, current_state: @user.access_state)
        )

        redirect_to admin_user_path(@user), notice: notice
        return
      end

      @user.access_state = to

      if @user.save
        set_admin_audit_context(
          action: audit_action,
          target_user: @user,
          metadata: transition_audit_metadata(previous_state: previous_state, current_state: @user.access_state)
        )

        redirect_to admin_user_path(@user), notice: notice
      else
        set_admin_audit_context(action: "#{audit_action}.failed", target_user: @user)
        render :show, status: :unprocessable_entity
      end
    end

    def transition_audit_metadata(previous_state:, current_state:)
      {
        previous_access_state: previous_state,
        current_access_state: current_state,
        note: params[:audit_note].to_s.strip.presence
      }.compact
    end
  end
end
