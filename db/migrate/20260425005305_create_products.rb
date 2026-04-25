class CreateProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.string  :artikon_id, null: false
      t.string  :sku
      t.string  :ean
      t.string  :name, null: false
      t.string  :slug, null: false
      t.text    :description_html
      t.text    :description_short
      t.text    :description_clean
      t.references :manufacturer, foreign_key: true

      t.decimal :weight_kg, precision: 10, scale: 3, default: 0
      t.integer :tax_rate, default: 21
      t.string  :state, default: "new"
      t.string  :currency, null: false, default: "CZK"

      t.integer :price_retail_cents,   null: false, default: 0
      t.integer :price_dealer_cents,   null: false, default: 0
      t.integer :price_wo_tax_cents,   null: false, default: 0

      t.integer :stock_amount, null: false, default: 0
      t.string  :availability_label
      t.integer :availability_days
      t.string  :item_group_id
      t.string  :supplier_url
      t.string  :manufacturer_part_number

      t.boolean :active, null: false, default: true
      t.boolean :topseller, null: false, default: false
      t.datetime :synced_at
      t.timestamps
    end
    add_index :products, :artikon_id, unique: true
    add_index :products, :slug, unique: true
    add_index :products, :sku
    add_index :products, :ean
    add_index :products, :active
    add_index :products, [:manufacturer_id, :active]
    add_index :products, :topseller
    add_index :products, :name, opclass: :gin_trgm_ops, using: :gin
  end
end
