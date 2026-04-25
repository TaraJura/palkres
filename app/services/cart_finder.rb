class CartFinder
  def initialize(session:, user: nil)
    @session = session
    @user = user
  end

  def call
    token = @session[:cart_token] ||= SecureRandom.hex(16)
    cart = Cart.find_or_create_by!(session_token: token)
    if @user && cart.user_id != @user.id
      cart.update!(user: @user)
    end
    cart
  end
end
