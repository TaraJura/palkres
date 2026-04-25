class CreateManufacturers < ActiveRecord::Migration[8.1]
  def change
    create_table :manufacturers do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.timestamps
    end
    add_index :manufacturers, :slug, unique: true
    add_index :manufacturers, :name, unique: true
  end
end
