import { Controller } from "@hotwired/stimulus"

// Appends the next page of products into #products-grid without losing the
// current page (Pavel's "previous stays open" request).
//
// Markup:
//   <div data-controller="load-more">
//     <div id="products-grid" data-load-more-target="grid">…</div>
//     <div id="load-more-wrapper" data-load-more-target="wrapper">
//       <a href="?page=2" data-action="click->load-more#load">Načíst další</a>
//     </div>
//   </div>
export default class extends Controller {
  static targets = ["grid", "wrapper"]

  async load(event) {
    event.preventDefault()
    const link = event.currentTarget
    if (link.dataset.loading === "1") return
    link.dataset.loading = "1"

    const originalText = link.textContent
    link.textContent = "Načítám…"
    link.classList.add("opacity-60", "pointer-events-none")

    try {
      const res = await fetch(link.href, { headers: { Accept: "text/html" } })
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const html = await res.text()
      const doc = new DOMParser().parseFromString(html, "text/html")

      const newGrid = doc.getElementById("products-grid")
      const newWrapper = doc.getElementById("load-more-wrapper")

      if (newGrid && this.hasGridTarget) {
        // Append only the cards from the next page (don't duplicate)
        const fragment = document.createDocumentFragment()
        Array.from(newGrid.children).forEach((node) => fragment.appendChild(node))
        this.gridTarget.appendChild(fragment)
      }

      if (this.hasWrapperTarget) {
        if (newWrapper) {
          this.wrapperTarget.outerHTML = newWrapper.outerHTML
        } else {
          this.wrapperTarget.remove()
        }
      }

      // Update URL so refresh keeps user on the loaded page
      try { history.replaceState({}, "", link.href) } catch (_) {}
    } catch (err) {
      console.error("load-more failed", err)
      link.textContent = originalText
      link.classList.remove("opacity-60", "pointer-events-none")
      link.dataset.loading = "0"
    }
  }
}
