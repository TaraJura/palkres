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

  GROUP_KEY_SQL = "COALESCE(products.item_group_id, 'p-' || products.id::text)".freeze

  # Collapse variants into a single representative product per `item_group_id`
  # (cheapest active variant wins; ungrouped products are their own group via the
  # 'p-<id>' fallback). Returns a fresh scope so the caller can apply ordering
  # and pagination without the joins from `scope` interfering.
  def self.one_per_variant_group_of(scope)
    rep_ids = scope.unscope(:order, :limit, :offset)
                   .distinct(false)
                   .select(Arel.sql("DISTINCT ON (#{GROUP_KEY_SQL}) products.id"))
                   .reorder(Arel.sql("#{GROUP_KEY_SQL}, products.price_retail_cents ASC NULLS LAST, products.id ASC"))
    where(id: rep_ids)
  end

  # Map of item_group_id => variant count for the given products. Use to badge
  # listing cards with "X variant" when count > 1.
  def self.variant_counts_for(products)
    group_ids = products.filter_map(&:item_group_id).uniq
    return {} if group_ids.empty?
    active.where("price_retail_cents > 0")
          .where(item_group_id: group_ids)
          .group(:item_group_id).count
  end

  validates :artikon_id, presence: true, uniqueness: true
  validates :name, presence: true

  # Per-variant image (the SHOPITEM's own IMAGE_BIG). On ARTIKON, many variants
  # carry only a 60×24 placeholder when the supplier doesn't have a per-color photo.
  def primary_image_url
    product_images.first&.url
  end

  alias_method :variant_image_url, :primary_image_url

  # Family/product image — the ARTIKON ITEMGROUP_ID photo. This is the picture
  # shown on listings (one card per family) and as the main hero on the product
  # detail page when the product has variants. Falls back to the variant image
  # when the group image is unknown (singletons, non-numeric ITEMGROUP_ID).
  def family_image_url
    group_image_url.presence || primary_image_url
  end

  def price_for(user)
    return price_dealer if user&.dealer?
    price_retail
  end

  def in_stock?
    stock_amount.to_i > 0
  end

  # Other products in the same ARTIKON ITEMGROUP (e.g. all colors of one paint family).
  # Returns ActiveRecord::Relation; caller can `.includes(:manufacturer).order(:name)`.
  def variants
    return Product.none if item_group_id.blank?
    self.class.active.where(item_group_id: item_group_id).where("price_retail_cents > 0")
  end

  def has_variants?
    item_group_id.present? && variants.where.not(id: id).exists?
  end

  # ARTIKON product names follow "Family Name size – CODE Color name".
  # variant_label returns just the part after the last en-dash (the color), or
  # the full name when no en-dash is present.
  def variant_label
    parts = name.split(/\s+[–—-]\s+/)
    parts.length > 1 ? parts.last : name
  end

  # Family name = name minus the variant_label suffix (best-effort).
  def variant_family_name
    if name.match?(/\s+[–—-]\s+/)
      name.split(/\s+[–—-]\s+/, 2).first.strip
    else
      name
    end
  end
end
