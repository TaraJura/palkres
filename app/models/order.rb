class Order < ApplicationRecord
  belongs_to :user, optional: true
  has_many :order_items, dependent: :destroy
  has_many :payments, dependent: :destroy
  has_many :shipments, dependent: :destroy

  enum :status,         { cart: 0, placed: 1, processing: 2, shipped: 3, delivered: 4, cancelled: 5 }, default: :cart, prefix: true
  enum :payment_state,  { pending: 0, authorized: 1, paid: 2, refunded: 3, failed: 4 }, default: :pending, prefix: :payment
  enum :shipping_state, { pending: 0, label_printed: 1, handed_over: 2, delivered: 3 }, default: :pending, prefix: :shipping

  monetize :subtotal_cents, as: :subtotal, with_model_currency: :currency
  monetize :shipping_cents, as: :shipping, with_model_currency: :currency
  monetize :tax_cents,      as: :tax,      with_model_currency: :currency
  monetize :total_cents,    as: :total,    with_model_currency: :currency

  before_validation :assign_number, on: :create

  validates :number, presence: true, uniqueness: true
  validates :email, presence: true

  def recompute_totals!
    self.subtotal_cents = order_items.sum(:line_total_cents)
    self.tax_cents      = (subtotal_cents * 0.21).round
    self.total_cents    = subtotal_cents + shipping_cents
    save!
  end

  private

  def assign_number
    self.number ||= "PK-#{Time.current.strftime('%Y%m')}-#{SecureRandom.hex(3).upcase}"
  end
end
