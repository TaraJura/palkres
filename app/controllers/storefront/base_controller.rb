class Storefront::BaseController < ApplicationController
  allow_unauthenticated_access

  before_action :load_category_tree

  private

  def load_category_tree
    @root_categories = Rails.cache.fetch("storefront:root_categories:v1", expires_in: 10.minutes) do
      roots = Category.roots.where("products_count > 0").order(:name).to_a
      roots.any? ? roots : Category.roots.order(:name).to_a # fallback if counters not yet backfilled
    end
  end
end
