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
    item.quantity = item.persisted? ? item.quantity.to_i + quantity : quantity
    item.unit_price_cents = product.price_retail_cents
    item.save!
    item
  end

  # entries = [{ product_id:, quantity: }, …]; quantities <= 0 are skipped.
  # Returns the number of distinct products actually added/updated.
  def add_many(entries)
    added = 0
    transaction do
      entries.each do |e|
        qty = e[:quantity].to_i.clamp(0, 99)
        next if qty.zero?
        product = Product.active.find_by(id: e[:product_id])
        next unless product
        add_product(product, quantity: qty)
        added += 1
      end
    end
    added
  end
end
