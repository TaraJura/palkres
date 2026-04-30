class Storefront::CartController < Storefront::BaseController
  def show
    @cart = current_cart
  end

  def add
    product = Product.active.find(params[:product_id])
    current_cart.add_product(product, quantity: params[:quantity].to_i.clamp(1, 99))
    redirect_to kosik_path, notice: "Přidáno do košíku: #{product.name}", status: :see_other
  end

  def bulk_add
    # The form posts items as `items[0][product_id]=…&items[0][quantity]=…`,
    # so Rails parses params[:items] as ActionController::Parameters keyed by
    # the index ("0", "1", …). Iterate values, not pairs.
    raw_items = params[:items]
    rows = raw_items.respond_to?(:values) ? raw_items.values : Array(raw_items)
    entries = rows.filter_map do |row|
      next unless row.respond_to?(:[])
      { product_id: row[:product_id].to_i, quantity: row[:quantity].to_i }
    end
    added = current_cart.add_many(entries)

    if added.zero?
      redirect_back fallback_location: kosik_path,
                    alert: "Nezadali jste žádný počet kusů. Vyberte alespoň jednu variantu.",
                    status: :see_other
    else
      msg = added == 1 ? "Přidáno do košíku: 1 varianta" : "Přidáno do košíku: #{added} variant"
      redirect_to kosik_path, notice: msg, status: :see_other
    end
  end

  def update
    item = current_cart.cart_items.find(params[:id])
    item.update!(quantity: params[:quantity].to_i.clamp(1, 99))
    redirect_to kosik_path
  end

  def remove
    current_cart.cart_items.find(params[:id]).destroy
    redirect_to kosik_path, notice: "Položka odstraněna"
  end
end
