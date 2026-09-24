class BankConnection < ApplicationRecord
  belongs_to :budget_workspace
  belongs_to :actor_membership, class_name: "WorkspaceMembership"
  has_many :connected_accounts, dependent: :restrict_with_error
  has_many :bank_refreshes, dependent: :restrict_with_error
  validates :status, inclusion: { in: %w[connecting active needs_attention disconnected] }
  validates :name, :claim_fingerprint, presence: true
  self.filter_attributes += [ :encrypted_access_url, :claim_fingerprint ]

  def access_url
    BankConnections::CredentialCodec.decode(encrypted_access_url) if encrypted_access_url.present?
  end

  def access_url=(value)
    self.encrypted_access_url = value.present? ? BankConnections::CredentialCodec.encode(value) : nil
  end

  def connected?
    status == "active" && encrypted_access_url.present?
  end
end
