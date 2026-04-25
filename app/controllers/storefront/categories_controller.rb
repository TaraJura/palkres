class Storefront::CategoriesController < Storefront::BaseController
  def show
    slug = params[:path].to_s.split("/").last
    @category = Category.friendly.find(slug)
    scope = @category.subtree.pluck(:id)
    products = Product.active.where("price_retail_cents > 0")
                      .joins(:product_categories)
                      .where(product_categories: { category_id: scope })
                      .distinct

    if params[:manufacturer_id].present?
      products = products.where(manufacturer_id: params[:manufacturer_id])
    end

    products = products.order(sort_column => sort_direction)

    @pagy, @products = pagy(products)
    @subcategories = @category.children.order(:name)
    @manufacturers_for_facet = Manufacturer.where(id: products.reorder(nil).distinct.pluck(:manufacturer_id).compact).order(:name)
  end

  private

  def sort_column
    %w[name price_retail_cents synced_at].include?(params[:sort]) ? params[:sort] : :name
  end

  def sort_direction
    params[:dir] == "desc" ? :desc : :asc
  end
end
