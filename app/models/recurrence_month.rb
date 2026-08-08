class RecurrenceMonth < ApplicationRecord
  belongs_to :recurrence_rule

  validates :month_number,
    inclusion: { in: 1..12 },
    uniqueness: { scope: :recurrence_rule_id }
end
