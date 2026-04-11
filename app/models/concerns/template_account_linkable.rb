module TemplateAccountLinkable
  extend ActiveSupport::Concern

  included do
    class_attribute :template_account_association_name, instance_writer: false, default: nil
    class_attribute :entry_account_association_name, instance_writer: false, default: nil

    validate :linked_template_account_belongs_to_user
  end

  class_methods do
    def template_account_association(name)
      self.template_account_association_name = name
      self.entry_account_association_name ||= name
    end

    def entry_account_association(name)
      self.entry_account_association_name = name
    end
  end

  def account_name
    entry_account_record&.name.presence || account
  end

  def entry_account_record
    return template_account_record if entry_account_association_name.blank?

    public_send(entry_account_association_name)
  end

  private

  def linked_template_account_belongs_to_user
    linked_account = template_account_record
    return if linked_account.blank? || linked_account.user_id == user_id

    errors.add(template_account_association_name, "must belong to the same user")
  end

  def template_account_record
    return nil if template_account_association_name.blank?

    public_send(template_account_association_name)
  end

  def template_account_association_name
    self.class.template_account_association_name
  end

  def entry_account_association_name
    self.class.entry_account_association_name
  end
end
