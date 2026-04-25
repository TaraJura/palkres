class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.string :number, null: false
      t.references :user, foreign_key: true
      t.string :email, null: false
      t.string :phone
      t.integer :status, null: false, default: 0
      t.integer :payment_state, null: false, default: 0
      t.integer :shipping_state, null: false, default: 0

      t.integer :subtotal_cents, null: false, default: 0
      t.integer :shipping_cents, null: false, default: 0
      t.integer :tax_cents,      null: false, default: 0
      t.integer :total_cents,    null: false, default: 0
      t.string  :currency, null: false, default: "CZK"

      t.string  :payment_method
      t.string  :shipping_method
      t.jsonb   :billing_address, null: false, default: {}
      t.jsonb   :shipping_address, null: false, default: {}
      t.text    :notes
      t.datetime :placed_at
      t.timestamps
    end
    add_index :orders, :number, unique: true
    add_index :orders, [:status, :created_at]

    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true
      t.references :product, foreign_key: true
      t.string :name_snapshot, null: false
      t.string :sku_snapshot
      t.integer :quantity, null: false
      t.integer :unit_price_cents, null: false
      t.integer :line_total_cents, null: false
      t.timestamps
    end
  end
end
