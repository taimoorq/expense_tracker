class AdminUser < ApplicationRecord
  devise :database_authenticatable, :rememberable, :validatable, :lockable

  has_many :admin_audit_logs, dependent: :restrict_with_error
  has_many :audit_events, foreign_key: :actor_admin_user_id, dependent: :restrict_with_error
end
