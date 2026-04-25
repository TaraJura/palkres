module ApplicationHelper
  include Pagy::Frontend

  def page_title(extra = nil)
    [extra, "Palkres — výtvarné potřeby"].compact_blank.join(" · ")
  end

  def format_price_cents(cents, currency: "CZK")
    Money.new(cents.to_i, currency).format
  end

  def category_path_for(category)
    category_path(path: category.path.map(&:slug).join("/"))
  end
end
