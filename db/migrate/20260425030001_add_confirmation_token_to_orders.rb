class AddConfirmationTokenToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :confirmation_token, :string
    add_index  :orders, :confirmation_token, unique: true
  end
end
