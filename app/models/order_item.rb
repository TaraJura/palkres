class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product, optional: true

  monetize :unit_price_cents, as: :unit_price, with_model_currency: :currency
  monetize :line_total_cents, as: :line_total, with_model_currency: :currency

  def currency
    order&.currency || "CZK"
  end
end
