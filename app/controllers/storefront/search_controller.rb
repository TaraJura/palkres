class Storefront::SearchController < Storefront::BaseController
  def show
    @query = params[:q].to_s.strip
    scope = Product.active.where("price_retail_cents > 0")
    if @query.present?
      scope = scope.where("unaccent(name) ILIKE unaccent(?) OR sku ILIKE ? OR ean = ?",
                          "%#{@query}%", "#{@query}%", @query)
    end
    @pagy, @products = pagy(scope.order(:name))
  end
end
