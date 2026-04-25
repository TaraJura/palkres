class Admin::DashboardController < Admin::BaseController
  def show
    @products_total      = Product.count
    @products_active     = Product.active.count
    @products_topseller  = Product.topsellers.count
    @products_no_image   = Product.left_joins(:product_images).where(product_images: { id: nil }).count
    @orders_total        = Order.where.not(status: :cart).count
    @orders_placed       = Order.status_placed.count
    @orders_processing   = Order.status_processing.count
    @orders_shipped      = Order.status_shipped.count
    @revenue_paid_cents  = Order.payment_paid.sum(:total_cents)
    @revenue_pending_cents = Order.where.not(status: :cart).where(payment_state: :pending).sum(:total_cents)
    @last_sync           = SyncRun.where(source: "artikon").order(started_at: :desc).first
    @recent_syncs        = SyncRun.where(source: "artikon").order(started_at: :desc).limit(5)
    @recent_orders       = Order.where.not(status: :cart).order(created_at: :desc).limit(8)
  end
end
