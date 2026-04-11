module Recurring
  class PlanningTemplateAccountLinking
    TEMPLATE_ASSOCIATIONS = [
      {
        relation: :pay_schedules,
        includes: :linked_account,
        association: :linked_account,
        id_attribute: :linked_account_id
      },
      {
        relation: :subscriptions,
        includes: :linked_account,
        association: :linked_account,
        id_attribute: :linked_account_id
      },
      {
        relation: :monthly_bills,
        includes: :linked_account,
        association: :linked_account,
        id_attribute: :linked_account_id
      },
      {
        relation: :payment_plans,
        includes: :linked_account,
        association: :linked_account,
        id_attribute: :linked_account_id
      },
      {
        relation: :credit_cards,
        includes: :payment_account,
        association: :payment_account,
        id_attribute: :payment_account_id
      }
    ].freeze

    def self.resolved_account_name(record)
      record.respond_to?(:account_name) ? record.account_name : record.account
    end

    def self.relink_for(user)
      TEMPLATE_ASSOCIATIONS.each do |mapping|
        records = user.public_send(mapping[:relation]).includes(mapping[:includes])
        relink_records(user: user, records: records, association: mapping[:association], id_attribute: mapping[:id_attribute])
      end
    end

    def self.relink_records(user:, records:, association:, id_attribute:)
      records.find_each do |record|
        next if record.public_send(id_attribute).present?
        next if record.account.blank?

        matched_account = user.accounts.find_by(name: record.account)
        next if matched_account.blank?

        record.public_send("#{association}=", matched_account)
        record.save!
      end
    end
  end
end
