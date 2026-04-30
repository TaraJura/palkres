class AddGroupImageUrlToProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :group_image_url, :string
  end
end
