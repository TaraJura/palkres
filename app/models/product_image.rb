class ProductImage < ApplicationRecord
  belongs_to :product
  has_one_attached :file
end
