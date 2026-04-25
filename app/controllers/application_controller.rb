class ApplicationController < ActionController::Base
  include Authentication
  include Pagy::Backend

  # NOTE: Rails 8's allow_browser versions: :modern was rejecting iOS Safari with 406.
  # Removed for now — we don't depend on bleeding-edge CSS :has / web-push features.
  # If we need a floor later, use a specific version map, not the :modern preset.
  stale_when_importmap_changes

  helper_method :current_cart

  def current_cart
    @current_cart ||= CartFinder.new(session: session, user: Current.user).call
  end
end
