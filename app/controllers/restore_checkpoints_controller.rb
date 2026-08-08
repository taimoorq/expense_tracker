class RestoreCheckpointsController < ApplicationController
  def update
    workspace = current_user.legacy_owned_budget_workspace || raise(ActiveRecord::RecordNotFound)
    checkpoint = workspace.restore_checkpoints.find(params[:id])
    result = Platform::Backup::RestoreCheckpointRollback.call(user: current_user, checkpoint: checkpoint)

    if result[:success]
      redirect_to backup_restore_path, notice: "Recovery checkpoint restored. The rollback result was audited."
    else
      redirect_to backup_restore_path, alert: "Checkpoint restore failed safely: #{result[:error]}"
    end
  rescue Platform::Backup::RestoreCheckpointRollback::InvalidState,
    Platform::Backup::CheckpointCodec::InvalidCheckpoint => error
    redirect_to backup_restore_path, alert: error.message
  end
end
