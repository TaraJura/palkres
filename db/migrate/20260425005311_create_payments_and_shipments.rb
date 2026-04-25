class CreatePaymentsAndShipments < ActiveRecord::Migration[8.1]
  def change
    create_table :payments do |t|
      t.references :order, null: false, foreign_key: true
      t.string :gateway, null: false
      t.string :gateway_ref
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: "CZK"
      t.string :status, null: false, default: "pending"
      t.jsonb :raw_response, null: false, default: {}
      t.timestamps
    end
    add_index :payments, :gateway_ref

    create_table :shipments do |t|
      t.references :order, null: false, foreign_key: true
      t.string :carrier, null: false
      t.string :tracking_number
      t.string :label_url
      t.string :status, null: false, default: "pending"
      t.jsonb :raw_response, null: false, default: {}
      t.timestamps
    end
    add_index :shipments, :tracking_number
  end
end
