class Storefront::ProductsController < Storefront::BaseController
  def show
    @product = Product.active.friendly.find(params[:slug])
    @primary_category = @product.categories.joins(:product_categories)
                                .where(product_categories: { primary: true, product_id: @product.id })
                                .first || @product.categories.first
    @related = related_products
    ImageCacherJob.perform_later(@product.id) if @product.product_images.exists?(cached: false)
  end

  private

  def related_products
    return Product.none unless @primary_category
    Product.active.joins(:product_categories)
           .where(product_categories: { category_id: @primary_category.id })
           .where.not(id: @product.id)
           .limit(8)
  end
end
