class CreateAddresses < ActiveRecord::Migration[8.1]
  def change
    create_table :addresses do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :kind, null: false, default: 0
      t.string :company
      t.string :ico
      t.string :dic
      t.string :first_name
      t.string :last_name
      t.string :street, null: false
      t.string :city, null: false
      t.string :postal_code, null: false
      t.string :country_code, null: false, default: "CZ"
      t.string :phone
      t.timestamps
    end
  end
end
