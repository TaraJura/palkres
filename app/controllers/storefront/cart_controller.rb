class Storefront::CartController < Storefront::BaseController
  def show
    @cart = current_cart
  end

  def add
    product = Product.active.find(params[:product_id])
    current_cart.add_product(product, quantity: params[:quantity].to_i.clamp(1, 99))
    redirect_to kosik_path, notice: "Přidáno do košíku: #{product.name}", status: :see_other
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
