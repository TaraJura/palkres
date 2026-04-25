class ProductCategory < ApplicationRecord
  belongs_to :product
  belongs_to :category, counter_cache: :products_count
end
