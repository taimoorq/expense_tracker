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
        id_attribute: :payment_account_id,
        source_name_attribute: :payment_account,
        account_name_attribute: :account
      },
      {
        relation: :credit_cards,
        includes: :linked_account,
        association: :linked_account,
        id_attribute: :linked_account_id,
        source_name_attribute: :linked_account,
        account_name_attribute: nil,
        fallback_name_attribute: :name
      }
    ].freeze

    def self.resolved_account_name(record)
      record.respond_to?(:account_name) ? record.account_name : record.account
    end

    def self.relink_for(user, planning_template_data: nil)
      source_lookup = source_attributes_by_relation(planning_template_data)

      TEMPLATE_ASSOCIATIONS.each do |mapping|
        records = user.public_send(mapping[:relation]).includes(mapping[:includes])
        relink_records(user: user, records: records, mapping: mapping, source_lookup: source_lookup)
      end
    end

    def self.relink_records(user:, records:, mapping:, source_lookup:)
      records.find_each do |record|
        next if record.public_send(mapping[:id_attribute]).present?

        account_name = account_name_for(record, mapping, source_lookup)
        next if account_name.blank?

        matched_account = user.accounts.find_by(name: account_name)
        next if matched_account.blank?

        record.public_send("#{mapping[:association]}=", matched_account)
        record.save!
      end
    end

    def self.account_name_for(record, mapping, source_lookup)
      source_attributes = source_lookup.dig(mapping[:relation], record.name.to_s)
      source_name = source_attributes&.fetch(mapping[:source_name_attribute], nil) if mapping[:source_name_attribute]
      account_name_attribute = mapping.key?(:account_name_attribute) ? mapping[:account_name_attribute] : :account
      record_name = record.public_send(account_name_attribute) if account_name_attribute && record.respond_to?(account_name_attribute)
      fallback_name = record.public_send(mapping[:fallback_name_attribute]) if mapping[:fallback_name_attribute] && record.respond_to?(mapping[:fallback_name_attribute])

      source_name.presence || record_name.presence || fallback_name.presence
    end

    def self.source_attributes_by_relation(planning_template_data)
      data = planning_template_data.respond_to?(:deep_symbolize_keys) ? planning_template_data.deep_symbolize_keys : {}

      TEMPLATE_ASSOCIATIONS.each_with_object({}) do |mapping, lookup|
        relation = mapping[:relation]
        next if lookup.key?(relation)

        lookup[relation] = Array(data[relation]).index_by { |attributes| attributes[:name].to_s }
      end
    end
  end
end
