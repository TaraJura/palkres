class Storefront::CategoriesController < Storefront::BaseController
  SORTS = {
    "name_asc"   => { name: :asc },
    "name_desc"  => { name: :desc },
    "price_asc"  => { price_retail_cents: :asc },
    "price_desc" => { price_retail_cents: :desc },
    "newest"     => { synced_at: :desc }
  }.freeze
  PER_PAGE = [24, 48, 96].freeze

  def show
    slug = params[:path].to_s.split("/").last
    @category = Category.friendly.find(slug)
    @sort = SORTS.key?(params[:sort]) ? params[:sort] : "name_asc"
    @per_page = PER_PAGE.include?(params[:per_page].to_i) ? params[:per_page].to_i : 24

    subtree_ids = @category.subtree.pluck(:id)
    base = Product.active.where("price_retail_cents > 0")
                  .joins(:product_categories)
                  .where(product_categories: { category_id: subtree_ids })
                  .distinct

    grouped_base = Product.one_per_variant_group_of(base)
    @total_in_category = grouped_base.count

    @manufacturer_facets = Manufacturer.joins(:products).merge(grouped_base)
                                       .group("manufacturers.id", "manufacturers.name")
                                       .order(Arel.sql("COUNT(DISTINCT products.id) DESC"))
                                       .limit(20)
                                       .pluck("manufacturers.id", "manufacturers.name", Arel.sql("COUNT(DISTINCT products.id)"))

    products = grouped_base
    if params[:manufacturer_id].present?
      products = products.where(manufacturer_id: params[:manufacturer_id])
      @selected_manufacturer = Manufacturer.find_by(id: params[:manufacturer_id])
    end
    if params[:in_stock] == "1"
      products = products.where("stock_amount > 0")
    end

    @pagy, @products = pagy(products.order(SORTS[@sort]), limit: @per_page)
    @variant_counts = Product.variant_counts_for(@products)
    @subcategories = @category.children.order(name: :asc)
  end
end
