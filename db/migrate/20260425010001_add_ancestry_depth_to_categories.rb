class AddAncestryDepthToCategories < ActiveRecord::Migration[8.1]
  def change
    add_column :categories, :ancestry_depth, :integer, null: false, default: 0
  end
end
