class Account::OrdersController < Account::BaseController
  def index
    @pagy, @orders = pagy(Current.user.orders.order(created_at: :desc))
  end

  def show
    @order = Order.where(user: Current.user).or(Order.where(email: Current.user.email_address)).find(params[:id])
  end
end
