class Admin::BaseController < ApplicationController
  before_action :require_authentication
  before_action :require_admin

  layout "admin"

  private

  def require_admin
    redirect_to root_path, alert: "Přístup odepřen." unless Current.user&.admin?
  end
end
