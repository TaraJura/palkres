class Storefront::HomeController < Storefront::BaseController
  def show
    @featured_categories = @root_categories.first(6)
    @recent_products = Product.active.where("price_retail_cents > 0").order(synced_at: :desc).limit(12)
    @popular_manufacturers = Manufacturer.joins(:products).where(products: { active: true })
                                         .group("manufacturers.id").order("COUNT(products.id) DESC").limit(12)
  end
end
