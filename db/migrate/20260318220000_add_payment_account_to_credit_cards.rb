class AddPaymentAccountToCreditCards < ActiveRecord::Migration[8.1]
  def change
    add_reference :credit_cards, :payment_account, type: :uuid, foreign_key: { to_table: :accounts }, index: true
  end
end
