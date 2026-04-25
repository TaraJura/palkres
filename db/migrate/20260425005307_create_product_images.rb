class CreateProductImages < ActiveRecord::Migration[8.1]
  def change
    create_table :product_images do |t|
      t.references :product, null: false, foreign_key: true
      t.string  :url, null: false
      t.string  :url_big
      t.integer :position, null: false, default: 0
      t.boolean :cached, null: false, default: false
      t.timestamps
    end
    add_index :product_images, [:product_id, :position]
    add_index :product_images, :url
  end
end
