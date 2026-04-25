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

  # Tailwind-styled replacement for pagy_nav.
  # Renders prev / numbered pages / gaps / next as proper buttons.
  def pagy_nav_pretty(pagy)
    return "".html_safe if pagy.pages <= 1

    btn_base = "inline-flex items-center justify-center min-w-10 h-10 px-3 rounded-full border text-sm transition"
    btn_idle = "bg-white border-slate-200 text-slate-700 hover:bg-rose-50 hover:border-rose-300 hover:text-rose-700"
    btn_curr = "bg-rose-600 border-rose-600 text-white shadow-sm"
    btn_disabled = "bg-slate-50 border-slate-100 text-slate-300 cursor-not-allowed"

    parts = []

    # Prev
    parts << if pagy.prev
      link_to "← Předchozí", pagy_url_for(pagy, pagy.prev),
              class: "#{btn_base} #{btn_idle}", "aria-label": "Předchozí stránka", rel: "prev"
    else
      content_tag(:span, "← Předchozí", class: "#{btn_base} #{btn_disabled}")
    end

    # Pages — pagy.series yields strings, integers, or "gap" markers; current is wrapped in :current
    pagy.series.each do |item|
      case item
      when Integer, /\A\d+\z/
        page = item.to_i
        parts << link_to(page.to_s, pagy_url_for(pagy, page),
                         class: "#{btn_base} #{btn_idle}",
                         "aria-label": "Stránka #{page}")
      when String # current page wrapped, e.g. "5"
        parts << content_tag(:span, item.to_s, class: "#{btn_base} #{btn_curr}", "aria-current": "page")
      else # :gap or "gap"
        parts << content_tag(:span, "…", class: "min-w-6 h-10 inline-flex items-center justify-center text-slate-400")
      end
    end

    # Next
    parts << if pagy.next
      link_to "Další →", pagy_url_for(pagy, pagy.next),
              class: "#{btn_base} #{btn_idle}", "aria-label": "Další stránka", rel: "next"
    else
      content_tag(:span, "Další →", class: "#{btn_base} #{btn_disabled}")
    end

    content_tag(:nav, parts.join.html_safe,
                class: "flex flex-wrap items-center justify-center gap-1.5 my-6",
                role: "navigation", "aria-label": "Stránkování")
  end
end
