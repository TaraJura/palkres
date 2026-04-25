class Storefront::OrderConfirmationsController < Storefront::BaseController
  def show
    @order = Order.find_by!(number: params[:number])
    return if accessible?
    raise ActiveRecord::RecordNotFound
  end

  private

  def accessible?
    # Owner of the order (logged-in match)
    return true if Current.user && @order.user_id == Current.user.id
    # Guest with token from the redirect after checkout
    params[:token].present? && ActiveSupport::SecurityUtils.secure_compare(params[:token].to_s, @order.confirmation_token.to_s)
  end
end
