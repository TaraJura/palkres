class CreateCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :categories do |t|
      t.string :ancestry
      t.string :name, null: false
      t.string :slug, null: false
      t.string :external_path
      t.integer :products_count, null: false, default: 0
      t.timestamps
    end
    add_index :categories, :ancestry
    add_index :categories, :slug, unique: true
    add_index :categories, :external_path, unique: true
  end
end
