module TemplateAccountLinkable
  extend ActiveSupport::Concern

  included do
    validate :linked_template_account_belongs_to_user
  end

  class_methods do
    def template_account_association(name)
      class_attribute :template_account_association_name, instance_writer: false, default: name
    end
  end

  def account_name
    template_account_record&.name.presence || account
  end

  private

  def linked_template_account_belongs_to_user
    linked_account = template_account_record
    return if linked_account.blank? || linked_account.user_id == user_id

    errors.add(template_account_association_name, "must belong to the same user")
  end

  def template_account_record
    public_send(template_account_association_name)
  end

  def template_account_association_name
    self.class.template_account_association_name
  end
end
