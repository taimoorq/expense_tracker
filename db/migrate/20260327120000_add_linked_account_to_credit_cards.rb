class AddLinkedAccountToCreditCards < ActiveRecord::Migration[8.1]
  def change
    add_reference :credit_cards, :linked_account, type: :uuid, foreign_key: { to_table: :accounts }, index: true
  end
end
