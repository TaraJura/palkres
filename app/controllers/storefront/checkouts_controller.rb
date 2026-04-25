class Storefront::CheckoutsController < Storefront::BaseController
  def show
    @cart = current_cart
    redirect_to root_path, notice: "Košík je prázdný" if @cart.cart_items.empty?
  end

  def create
    @cart = current_cart
    attrs = params.require(:order).permit(:email, :phone, :notes, :shipping_method, :payment_method,
                                          billing: [:first_name, :last_name, :company, :street, :city, :postal_code, :country_code, :ico, :dic],
                                          shipping: [:first_name, :last_name, :street, :city, :postal_code, :country_code])

    order = Order.new(
      email: attrs[:email],
      phone: attrs[:phone],
      notes: attrs[:notes],
      shipping_method: attrs[:shipping_method].presence || "packeta",
      payment_method:  attrs[:payment_method].presence  || "bank_transfer",
      billing_address: attrs[:billing].to_h,
      shipping_address: (attrs[:shipping].presence || attrs[:billing]).to_h,
      user: Current.user,
      status: :placed,
      placed_at: Time.current
    )

    @cart.cart_items.includes(:product).each do |ci|
      order.order_items.build(
        product: ci.product,
        name_snapshot: ci.product.name,
        sku_snapshot:  ci.product.sku,
        quantity:      ci.quantity,
        unit_price_cents: ci.unit_price_cents,
        line_total_cents: ci.line_total_cents
      )
    end

    order.shipping_cents = 99_00 # placeholder flat-rate
    order.save!
    order.recompute_totals!
    @cart.cart_items.destroy_all

    redirect_to order_confirmation_path(number: order.number, token: order.confirmation_token),
                status: :see_other,
                notice: "Děkujeme! Objednávka #{order.number} byla odeslána."
  end
end
