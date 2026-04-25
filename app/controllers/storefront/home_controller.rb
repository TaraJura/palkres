class Storefront::HomeController < Storefront::BaseController
  def show
    @featured_categories = @root_categories.first(6)
    @recent_products     = Product.active.where("price_retail_cents > 0").order(synced_at: :desc).limit(8)
    @best_deals          = Product.active.where("price_retail_cents > 0").where("price_retail_cents < price_wo_tax_cents * 1.21 - 100")
                                  .order(price_retail_cents: :asc).limit(4)
    @popular_manufacturers = Manufacturer.joins(:products).where(products: { active: true })
                                         .group("manufacturers.id").order("COUNT(products.id) DESC").limit(12)
    @stats = {
      products:      Product.active.count,
      categories:    Category.where("products_count > 0").count,
      manufacturers: Manufacturer.joins(:products).distinct.count
    }
  end
end
