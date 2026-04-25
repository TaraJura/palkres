class Admin::DashboardController < Admin::BaseController
  def show
    @products_total = Product.count
    @products_active = Product.active.count
    @orders_pending = Order.status_placed.count
    @last_sync = SyncRun.where(source: "artikon").order(started_at: :desc).first
  end
end
