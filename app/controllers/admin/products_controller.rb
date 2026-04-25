class Admin::ProductsController < Admin::BaseController
  def index
    scope = Product.all.order(updated_at: :desc)
    scope = scope.where("name ILIKE ? OR sku ILIKE ? OR artikon_id = ?", "%#{params[:q]}%", "#{params[:q]}%", params[:q]) if params[:q].present?
    scope = scope.where(active: params[:active] == "1") if params[:active].present?
    @pagy, @products = pagy(scope, limit: 50)
  end

  def show
    @product = Product.find(params[:id])
  end

  def update
    @product = Product.find(params[:id])
    @product.update!(params.require(:product).permit(:active, :topseller))
    redirect_to admin_product_path(@product), notice: "Uloženo."
  end
end
