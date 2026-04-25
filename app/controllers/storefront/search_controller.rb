class Storefront::SearchController < Storefront::BaseController
  SORTS = {
    "relevance"  => nil,                      # default: best-match then name
    "name_asc"   => { name: :asc },
    "name_desc"  => { name: :desc },
    "price_asc"  => { price_retail_cents: :asc },
    "price_desc" => { price_retail_cents: :desc },
    "newest"     => { synced_at: :desc }
  }.freeze

  def show
    @query = params[:q].to_s.strip
    @sort  = SORTS.key?(params[:sort]) ? params[:sort] : "relevance"

    base = Product.active.where("price_retail_cents > 0")

    if @query.present?
      pattern = "%#{@query}%"
      base = base.where(
        "unaccent(products.name) ILIKE unaccent(?) OR products.sku ILIKE ? OR products.ean = ? OR products.manufacturer_part_number ILIKE ?",
        pattern, "#{@query}%", @query, "#{@query}%"
      )
    end

    @total_before_facets = base.count
    @price_range = base.pluck("MIN(price_retail_cents), MAX(price_retail_cents)").first || [0, 0]

    # Build manufacturer facet counts (top 20) BEFORE applying the manufacturer filter
    @manufacturer_facets = Manufacturer.joins(:products).merge(base)
                                       .group("manufacturers.id", "manufacturers.name")
                                       .order("COUNT(products.id) DESC")
                                       .limit(20)
                                       .pluck("manufacturers.id", "manufacturers.name", "COUNT(products.id)")

    scope = base

    if params[:manufacturer_id].present?
      scope = scope.where(manufacturer_id: params[:manufacturer_id])
      @selected_manufacturer = Manufacturer.find_by(id: params[:manufacturer_id])
    end

    if params[:in_stock] == "1"
      scope = scope.where("stock_amount > 0")
    end

    if params[:price_min].present?
      scope = scope.where("price_retail_cents >= ?", params[:price_min].to_i * 100)
    end

    if params[:price_max].present?
      scope = scope.where("price_retail_cents <= ?", params[:price_max].to_i * 100)
    end

    order_clause =
      if SORTS[@sort]
        SORTS[@sort]
      elsif @query.present?
        # relevance-ish: exact-start match first, then name A–Z
        Arel.sql(
          "CASE WHEN unaccent(products.name) ILIKE unaccent(#{ActiveRecord::Base.connection.quote(@query + '%')}) THEN 0 ELSE 1 END, products.name ASC"
        )
      else
        { name: :asc }
      end

    @pagy, @products = pagy(scope.order(order_clause))
  end
end
