class AdminUser < ApplicationRecord
  devise :database_authenticatable, :rememberable, :validatable

  has_many :admin_audit_logs, dependent: :nullify
end
