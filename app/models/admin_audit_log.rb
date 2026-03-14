class AdminAuditLog < ApplicationRecord
  belongs_to :admin_user
  belongs_to :target_user, class_name: "User", optional: true

  validates :action, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
end
