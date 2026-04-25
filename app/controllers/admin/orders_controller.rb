class Admin::OrdersController < Admin::BaseController
  def index
    scope = Order.includes(:order_items).order(created_at: :desc)

    if params[:q].present?
      scope = scope.where("orders.number ILIKE :p OR orders.email ILIKE :p", p: "%#{params[:q]}%")
    end

    if params[:status].present? && Order.statuses.key?(params[:status])
      scope = scope.where(status: params[:status])
    end

    @counts = {
      total:      Order.count,
      placed:     Order.status_placed.count,
      processing: Order.status_processing.count,
      shipped:    Order.status_shipped.count,
      delivered:  Order.status_delivered.count,
      cancelled:  Order.status_cancelled.count,
      pending_payment: Order.payment_pending.where.not(status: :cart).count
    }
    @revenue_paid = Order.payment_paid.sum(:total_cents)
    @pagy, @orders = pagy(scope, limit: 30)
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
