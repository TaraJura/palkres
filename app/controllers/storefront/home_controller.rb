class Storefront::HomeController < Storefront::BaseController
  def show
    @featured_categories = @root_categories.first(6)
    base = Product.active.where("price_retail_cents > 0")
    @recent_products = Product.one_per_variant_group_of(base).order(synced_at: :desc).limit(8)
    @variant_counts  = Product.variant_counts_for(@recent_products)
    @best_deals      = Product.one_per_variant_group_of(
                         base.where("price_retail_cents < price_wo_tax_cents * 1.21 - 100")
                       ).order(price_retail_cents: :asc).limit(4)
    @popular_manufacturers = Manufacturer.joins(:products).where(products: { active: true })
                                         .group("manufacturers.id").order("COUNT(products.id) DESC").limit(12)
    @stats = {
      products:      Product.one_per_variant_group_of(base).count,
      categories:    Category.where("products_count > 0").count,
      manufacturers: Manufacturer.joins(:products).distinct.count
    }
  end
end
