class Admin::OrdersController < Admin::BaseController
  def index
    @pagy, @orders = pagy(Order.order(created_at: :desc), limit: 50)
  end

  def show
    @order = Order.find(params[:id])
  end

  def update
    @order = Order.find(params[:id])
    @order.update!(params.require(:order).permit(:status, :payment_state, :shipping_state))
    redirect_to admin_order_path(@order), notice: "Stav uložen."
  end
end
