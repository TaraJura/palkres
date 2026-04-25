class CartItem < ApplicationRecord
  belongs_to :cart
  belongs_to :product

  monetize :unit_price_cents, as: :unit_price, with_model_currency: :currency

  def line_total_cents
    quantity.to_i * unit_price_cents.to_i
  end

  def currency
    "CZK"
  end
end
