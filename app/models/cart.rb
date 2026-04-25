class Cart < ApplicationRecord
  belongs_to :user, optional: true
  has_many :cart_items, dependent: :destroy
  has_many :products, through: :cart_items

  def subtotal_cents
    cart_items.sum("quantity * unit_price_cents")
  end

  def item_count
    cart_items.sum(:quantity)
  end

  def add_product(product, quantity: 1)
    item = cart_items.find_or_initialize_by(product_id: product.id)
    item.quantity = item.quantity.to_i + quantity
    item.unit_price_cents = product.price_retail_cents
    item.save!
    item
  end
end
