class ApplicationController < ActionController::Base
  include Authentication
  include Pagy::Backend

  allow_browser versions: :modern
  stale_when_importmap_changes

  helper_method :current_cart

  def current_cart
    @current_cart ||= CartFinder.new(session: session, user: Current.user).call
  end
end
