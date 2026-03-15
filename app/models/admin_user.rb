class AdminUser < ApplicationRecord
  devise :database_authenticatable, :rememberable, :validatable, :lockable

  has_many :admin_audit_logs, dependent: :nullify
end
