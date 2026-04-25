class CreateCarts < ActiveRecord::Migration[8.1]
  def change
    create_table :carts do |t|
      t.references :user, foreign_key: true
      t.string :session_token, null: false
      t.timestamps
    end
    add_index :carts, :session_token, unique: true

    create_table :cart_items do |t|
      t.references :cart, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.integer :quantity, null: false, default: 1
      t.integer :unit_price_cents, null: false, default: 0
      t.timestamps
    end
    add_index :cart_items, [:cart_id, :product_id], unique: true
  end
end
