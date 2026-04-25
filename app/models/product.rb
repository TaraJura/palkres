class Product < ApplicationRecord
  extend FriendlyId
  friendly_id :name, use: :slugged

  belongs_to :manufacturer, optional: true
  has_many :product_categories, dependent: :destroy
  has_many :categories, through: :product_categories
  has_many :product_images, -> { order(:position) }, dependent: :destroy

  monetize :price_retail_cents,   as: :price_retail,   with_model_currency: :currency
  monetize :price_dealer_cents,   as: :price_dealer,   with_model_currency: :currency
  monetize :price_wo_tax_cents,   as: :price_wo_tax,   with_model_currency: :currency

  scope :active, -> { where(active: true) }
  scope :topsellers, -> { where(topseller: true) }
  scope :in_stock, -> { where("stock_amount > 0") }

  validates :artikon_id, presence: true, uniqueness: true
  validates :name, presence: true

  def primary_image_url
    product_images.first&.url
  end

  def price_for(user)
    return price_dealer if user&.dealer?
    price_retail
  end

  def in_stock?
    stock_amount.to_i > 0
  end
end
