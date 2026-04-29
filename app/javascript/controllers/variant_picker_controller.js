import { Controller } from "@hotwired/stimulus"

// Live "selected pieces / selected price" badge for the variant grid.
// Markup expectations:
//   <form data-controller="variant-picker" data-variant-picker-currency-value="Kč">
//     <input data-variant-picker-target="qty" data-unit-cents="1234" type="number" name="items[…][quantity]" min="0" max="99">
//     …
//     <button data-variant-picker-target="submit">…</button>
//     <span data-variant-picker-target="total">0</span>
//     <span data-variant-picker-target="totalPrice">0 Kč</span>
//   </form>
export default class extends Controller {
  static targets = ["qty", "total", "totalPrice", "submit", "rowTotal"]

  connect() {
    this.recalc()
  }

  step(event) {
    const input = event.currentTarget
                       .closest("[data-row]")
                       ?.querySelector("[data-variant-picker-target~='qty']")
    if (!input) return
    const dir = parseInt(event.currentTarget.dataset.dir || "0", 10)
    const next = Math.max(0, Math.min(99, (parseInt(input.value || "0", 10) || 0) + dir))
    input.value = next
    this.recalc()
  }

  recalc() {
    let totalQty = 0
    let totalCents = 0

    this.qtyTargets.forEach((q) => {
      const qty = Math.max(0, Math.min(99, parseInt(q.value || "0", 10) || 0))
      const cents = parseInt(q.dataset.unitCents || "0", 10) || 0
      totalQty += qty
      totalCents += qty * cents

      // Per-row subtotal label, if present in the row
      const row = q.closest("[data-row]")
      const rowTotal = row?.querySelector("[data-variant-picker-target~='rowTotal']")
      if (rowTotal) {
        rowTotal.textContent = qty > 0 ? this.format(qty * cents) : ""
      }
      if (row) {
        row.classList.toggle("bg-rose-50/40", qty > 0)
        row.classList.toggle("ring-1", qty > 0)
        row.classList.toggle("ring-rose-200", qty > 0)
      }
    })

    if (this.hasTotalTarget) this.totalTarget.textContent = totalQty
    if (this.hasTotalPriceTarget) this.totalPriceTarget.textContent = this.format(totalCents)

    if (this.hasSubmitTarget) {
      const disabled = totalQty === 0
      this.submitTarget.disabled = disabled
      this.submitTarget.classList.toggle("opacity-60", disabled)
      this.submitTarget.classList.toggle("cursor-not-allowed", disabled)
    }
  }

  format(cents) {
    const v = (cents / 100)
    // CZ format: 1 234,50 Kč
    const fixed = v.toFixed(2).replace(".", ",").replace(/\B(?=(\d{3})+(?!\d))/g, " ")
    return `${fixed} Kč`
  }
}
