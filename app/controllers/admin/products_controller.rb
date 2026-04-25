class Admin::ProductsController < Admin::BaseController
  def index
    scope = Product.includes(:manufacturer).order(updated_at: :desc)

    if params[:q].present?
      pattern = "%#{params[:q]}%"
      scope = scope.where(
        "products.name ILIKE :p OR products.sku ILIKE :p OR products.artikon_id = :exact OR products.ean = :exact",
        p: pattern, exact: params[:q]
      )
    end

    case params[:filter]
    when "active"     then scope = scope.where(active: true)
    when "inactive"   then scope = scope.where(active: false)
    when "topseller"  then scope = scope.where(topseller: true)
    when "out_of_stock" then scope = scope.where("stock_amount <= 0")
    when "no_image"   then scope = scope.left_joins(:product_images).where(product_images: { id: nil })
    end

    if params[:manufacturer_id].present?
      scope = scope.where(manufacturer_id: params[:manufacturer_id])
    end

    @counts = {
      total:        Product.count,
      active:       Product.where(active: true).count,
      inactive:     Product.where(active: false).count,
      topseller:    Product.where(topseller: true).count,
      out_of_stock: Product.where("stock_amount <= 0").count
    }
    @manufacturers = Manufacturer.order(:name)
    @pagy, @products = pagy(scope, limit: 30)
  end

  def show
    @product = Product.friendly.find(params[:id])
  end

  def update
    @product = Product.friendly.find(params[:id])
    @product.update!(params.require(:product).permit(:active, :topseller))
    redirect_to admin_product_path(@product), notice: "Uloženo."
  end
end
