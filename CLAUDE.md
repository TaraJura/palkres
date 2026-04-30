# CLAUDE.md — Palkres e-shop

Rails 8.1.2 + PostgreSQL e-shop for **Palkres s.r.o.** (art & stationery supplies).
Primary supplier: **ARTIKON s.r.o.** via XML feed.

## 🔴 CRITICAL — Source of truth: ARTIKON XML feed

**The single canonical product feed is:**

```
https://www.artikon.cz/feeds/xml/VO_XML_Feed_Komplet_2.xml
```

- ~163 MB, ~29 222 `<SHOPITEM>` entries, gzipped at edge but Rails fetches the uncompressed XML.
- Cached locally at `tmp/artikon/feed.xml` after every successful fetch (gitignored).
- **All catalog state in the database is downstream of this feed** — products, categories, manufacturers, prices, stock, images. If something looks wrong in the DB, *re-read the feed first* before assuming a code bug. The feed is the source of truth; the DB is a derived view.
- Every `<SHOPITEM>` is one ARTIKON variant — `IMAGE` / `IMAGE_BIG` / `IMAGE_BIG_NOWM` are per-variant URLs (often a placeholder if the variant has no own photo); `ITEMGROUP_ID` groups variants and the **group-level image lives at `https://www.artikon.cz/deploy/img/products/<ITEMGROUP_ID>/<ITEMGROUP_ID>.jpg`** even though no SHOPITEM emits that URL — derive it when the per-variant image returns a 60×24 placeholder.
- See **Rule 5** for the SAX-streaming requirement (never `Nokogiri::XML(File.read(feed))`).
- See `app/services/artikon/{feed_fetcher,feed_sax_handler,feed_importer}.rb` for the only legitimate consumers.

Any change to import, image handling, pricing, stock, or category logic **must** be validated against the feed contents above before shipping.

## At-a-glance

- **Location**: `/home/novakj/palkres-eshop`
- **GitHub**: `git@github.com:TaraJura/palkres.git` (single `main` branch)
- **Live URL**: <https://palkres.techtools.cz> (Let's Encrypt TLS auto-renewed via certbot timer)
- **Admin URL**: `/admin` — credentials seeded in `db/seeds.rb`. Rotate via console: `User.find_by(email_address: …).update!(password: …)`
- **Ruby / Rails**: 4.0.1 / 8.1.2
- **Database**: PostgreSQL 17 (role `palkres`, DBs `palkres_eshop_{development,test,production}` + 3 `_production_{cache,queue,cable}` for Solid)
- **Port (prod)**: 3003, behind nginx on `palkres.techtools.cz` → systemd `palkres-eshop.service` (Puma 8 single mode + Solid Queue plugin)
- **Supplier feed**: see CRITICAL section above.
- **Bank for QR-platba**: configured via `.env` (`PALKRES_BANK_IBAN`, `PALKRES_BANK_NAME`). `Payments::CzechQr.placeholder?` short-circuits when the IBAN is one of the known placeholders.
- **Outgoing e-mail**: SMTP wired but disabled until `SMTP_HOST/PORT/USER/PASS/DOMAIN` are set in `.env` (currently `:test` delivery).

## How it works

### Catalog
1. A nightly Solid Queue job (`ArtikonSyncJob`) fetches the ARTIKON feed using
   `If-Modified-Since` / ETag. If 304, no-op.
2. The feed is **streamed** through `Nokogiri::XML::SAX::Parser` —
   `Artikon::FeedSaxHandler` yields one `SHOPITEM` hash per `end_element :SHOPITEM`.
3. `Artikon::FeedImporter` runs two passes:
   - **Pass 1**: collect every `CATEGORIES/CAT` path, ensure `Category` tree via
     `ancestry` gem (parse `"A / B / C"` → nested nodes).
   - **Pass 2**: upsert `Product` rows in batches of 500 via `upsert_all(unique_by: :artikon_id)`,
     then sync `product_categories` + `product_images`.
4. Products missing from the feed are soft-deactivated (`active = false`) rather
   than destroyed — orders reference products historically.
5. `SyncRun` records the outcome (items_seen/created/updated/deactivated, errors jsonb).
6. Product images are NOT downloaded during import — `ProductImage#url` stores the
   ARTIKON CDN URL. On first product-detail view, `ImageCacherJob` copies images
   into ActiveStorage in the background.

### Storefront (CZ)
- `/` — home, featured categories + top-sellers (`MERGADO_TOPSELLER=1`)
- `/kategorie/*path` — category listing w/ left-tree sidebar, pagy pagination, facets, per-page selector (24/48/96), "Načíst další" load-more
- `/produkt/:slug` — detail page, gallery, add to cart, **variant grid + bulk-add** for any product whose `item_group_id` has siblings (paint families, brush sizes, etc.)
- `/hledat?q=…` — FTS + trigram fuzzy, per-page selector (24/48/96), "Načíst další" load-more
- `/kosik` — Turbo-driven cart
- `/pokladna` — guest/user checkout (address → shipping → payment → confirm)
- `/uctu/*` — user's orders, addresses, profile

### Admin (`/admin/*`)
Role-gated (`User#role == "admin"`): products list, sync runs, manual "Sync now",
orders queue with status transitions.

### Payments & shipping
- `PaymentGateway` interface → `GoPayGateway` (first adapter, CZ-standard).
- `ShippingCarrier` interface → `PacketaCarrier` (Zásilkovna pickup-points) and
  `FlatRateCarrier` fallback.

## Critical project rules

### 1. NEVER start Rails manually in production
Production runs via **systemd** (`palkres-eshop.service`). Use:
```bash
sudo systemctl restart palkres-eshop.service
sudo journalctl -u palkres-eshop.service -f
```

### 2. Always backup before destructive DB operations
```bash
pg_dump -U palkres -h 127.0.0.1 palkres_eshop_production \
  > /home/novakj/backups/palkres_$(date +%Y%m%d_%H%M%S).sql
```

### 3. File permissions (nginx = www-data)
```bash
chmod 644 <new-file>      # files
chmod 755 <new-dir>       # directories
```

### 4. ALWAYS read files before editing
Never propose changes to code you haven't read.

### 5. The SAX parser is NON-NEGOTIABLE for import
The feed is 163 MB. Never `Nokogiri::XML(File.read(feed))` — use
`Nokogiri::XML::SAX::Parser.new(Artikon::FeedSaxHandler.new { |item| … })`.

### 6. Monetary values are ALWAYS integer cents (`_cents`) + CZK
Use `money-rails`. Rendering: `humanized_money_with_symbol(product.price_retail)`.

### 7. Images are lazy — don't download 29k on import
`ImageCacherJob(product_id)` runs only on first detail-page view.

### 8. Category tree from ARTIKON uses `" / "` as separator
Split on `" / "` (space, slash, space). `CATEGORIES/CAT` can have multiple paths
per product → `product_categories` is many-to-many.

### 9. Working on `main` only
Don't create feature branches unless explicitly asked.

### 10. Mobile-first is non-negotiable — every UI change MUST start at the phone
Most Czech e-shop traffic is mobile. The phone breakpoint is the **default**, the desktop layout is the *enhancement* — never the other way around.

**Hard rules for any view, partial, or component:**

- **Default styles target phones (<640 px)**. Use Tailwind's `sm:`, `md:`, `lg:`, `xl:` modifiers to *add* desktop affordances. Do not write desktop-first CSS and patch in `max-w-*:` overrides.
- **Tap targets ≥ 44×44 px** (Apple HIG / WCAG 2.5.5 minimum). Buttons, links inside lists, icon-only controls — all must hit this size on touch.
- **Single-column by default**, multi-column only at `md:` (768 px) or larger. Tables on mobile must collapse to stacked card rows or be horizontally scrollable inside `overflow-x-auto`.
- **No hover-only interactions** — hover state may add polish on desktop, but every action must work via tap. No tooltips that hold critical info.
- **Sticky headers / footers** must not eat more than ~64 px of viewport height on mobile. The cart bar, search bar, and header logo each have a budget — don't pile up.
- **Forms**: label above field (not beside), full-width inputs, `type="email" | "tel" | "number" | "search"` to surface the correct mobile keyboard. Never rely on placeholder as label.
- **Images**: `loading="lazy"`, `object-contain` inside fixed aspect-ratio boxes, `srcset` once we cache locally — phone bandwidth matters.
- **Font sizes**: body ≥ 14 px on phones (Tailwind `text-sm` is 14 px — that's the floor), price/CTA ≥ 16 px, headlines scale up at `md:`.
- **Test recipe before merging any UI change**:
  1. DevTools → toggle device → iPhone 14 (390 px) and Galaxy S23 (412 px).
  2. Verify: nothing horizontal-scrolls, every button is tappable, header doesn't eat the page, cart counter stays visible, forms aren't squashed.
  3. Then check `md:` (768 px) and `lg:` (1024 px) — desktop should *gain* features, not break.
- **Lighthouse mobile** score should stay ≥ 85 for Performance and ≥ 95 for Accessibility on the home, category, and product pages. Run before shipping a major UI change.

When in doubt, *open the page on your phone first*. If the phone view feels cramped, broken, or hostile to touch, the change is not done.

### 11. The whole app is in Czech — every user-facing string MUST be in Czech
The audience is Czech consumers. Every label, button, placeholder, helper text, error message, e-mail subject, e-mail body, flash notice, page title, status name shown to users, empty-state copy, and admin section header must be in Czech. No English remnants.

**Where to look for English creep**:

- **Rails-generated scaffolds** ship with English strings (`Sign in`, `Forgot password?`, `Save`, `New …`). Translate every one immediately on generation — don't merge the scaffold and forget. The `sessions/new` and `passwords/{new,edit}` views were originally English; we replaced them on 2026-04-25 — same vigilance applies to anything `bin/rails generate` produces.
- **Default Rails validation messages** ("can't be blank", "is invalid", "is too short"). Set `config.i18n.default_locale = :cs` and provide a Czech translation file (`rails-i18n` gem is the cleanest source) before any form ships to a real user.
- **`Time#strftime` literal formats** — `%A` returns "Monday", not "pondělí". Use `I18n.l(time, format: …)` with a Czech locale, or write the format manually.
- **Money / number formatting** — Czech uses space as thousand separator and comma as decimal (`1 234,50 Kč`). `config/initializers/money.rb` already enforces this; don't undo it.
- **HTML `<title>` tags and meta descriptions** — every view should `content_for :title` with a Czech title.
- **Enum values rendered raw in views** (`order.status.humanize` → "Placed"). Either add a Czech-name helper (`AdminHelper#status_label_cs(status)`) or ship a translations YAML.
- **Form `placeholder`** — never English ("Enter email"). Use Czech ("vase@adresa.cz").
- **E-mail subject + body** (`OrderMailer`) — Czech only.
- **Admin pages too.** The fact that Palkres staff use them doesn't excuse English copy; the eventual user is Czech-speaking.

**The only acceptable English**:

- Code (variables, classes, methods, comments) — international convention, don't translate.
- HTTP / JSON keys for external APIs (GoPay, Packeta, ARTIKON feed) — those are wire-format, not UI.
- `lang="cs"` attribute on `<html>` — the value itself is technical.

**Recipe before merging any UI/text change**:

1. Grep the diff for English-only strings:
   ```bash
   git diff | grep -E "(Sign |Save\b|Submit\b|Forgot|Error\b|Welcome|New |Edit |Delete|Cancel|Back\b|Next\b|Search\b)"
   ```
   Any hit needs a Czech equivalent (or proves it's a code identifier, not user copy).
2. Open the page on the live site and skim every word.
3. Mailers: render `OrderMailer.confirmation(id).body` in console and confirm the subject + every line is Czech.

When in doubt, ask for the right Czech phrasing rather than inventing loose translations. Czech commerce tone is generally more formal ("Vaše objednávka byla přijata", not "Hotovo!").

### 12. Document EVERY change in this CLAUDE.md — no exceptions
Claude Code is the **architect and main developer** of this app. That role is not just a label — it carries the responsibility of keeping the project's institutional memory in this file. Every change to production (or to anything that ships to production) must leave a trail here.

**The rule (binding for every Claude session and every human contributor)**:

1. **Before** writing or modifying code that affects behavior, scan the relevant sections of this CLAUDE.md (Critical project rules, Data model, Key paths, Common commands).
2. **After** the change ships (commit pushed, service restarted, smoke-tested), append an entry to **Post-launch change log** at the top of that section. Entry format:

   ```markdown
   ### YYYY-MM-DD — short imperative title
   - What changed (user-visible) or what broke.
   - Root cause (if a fix).
   - Fix / implementation: file paths + a sentence per change.
   - Side effects, follow-ups, or new TODOs.
   ```

3. **If the change introduces a new convention, dependency, model, endpoint, or operational step**, also update the relevant *non-log* section (Data model table, Key paths, Common commands, Critical project rules) — the change log explains *why*, the structured sections explain *how it works now*.

4. **If the change is a one-off ops action** (db backfill, cache wipe, manual sync), still log it. Future-you needs to know it happened.

5. **No "I'll document it later"**. The commit, the systemd restart, and the change-log entry are one atomic unit. Logging is not optional cleanup — it's part of the change.

6. **Don't duplicate what git history already says**. Log the *intent*, *root cause*, and *gotchas* — those don't survive in a commit message. File paths and one-sentence summaries are enough; the diff has the rest.

7. **If you skip this**, the next session six months from now will rediscover the same bug, redo the same backfill, or fight the same convention. That cost is on you.

The change log is the **single source of truth for "what happened to Palkres"**. Git is secondary, journalctl is tertiary.

## Data model

| Model | Key fields |
|---|---|
| `User` | email_address (uniq), password_digest, role enum (customer / dealer / admin), first_name, last_name, phone |
| `Address` | user_id, kind enum (billing / shipping), company, ico, dic, first_name, last_name, street, city, postal_code, country_code, phone |
| `Category` | ancestry, ancestry_depth, slug (friendly_id), name, external_path, products_count (counter-cache, backfilled by importer SQL) |
| `Manufacturer` | slug, name |
| `Product` | artikon_id (uniq), sku, ean, slug, name, description_html, description_short, description_clean, manufacturer_id, weight_kg, tax_rate, state, currency, price_retail_cents, price_dealer_cents, price_wo_tax_cents, stock_amount, availability_label, availability_days, item_group_id, supplier_url, manufacturer_part_number, active, topseller, synced_at |
| `ProductCategory` | product_id, category_id, primary (bool) |
| `ProductImage` | product_id, url, url_big, position, cached (bool, true once attached to ActiveStorage) + `has_one_attached :file` |
| `Cart` | user_id (nullable), session_token (uniq) |
| `CartItem` | cart_id, product_id, quantity (default 1 — see cart-add fix in change log), unit_price_cents |
| `Order` | **number (uniq)**, **confirmation_token (uniq, urlsafe_base64)**, user_id (nullable for guest), email, phone, status enum (cart / placed / processing / shipped / delivered / cancelled, prefix: `status_*`), payment_state enum (pending / authorized / paid / refunded / failed, prefix: `payment_*`), shipping_state enum (pending / label_printed / handed_over / delivered, prefix: `shipping_*`), subtotal_cents, shipping_cents, tax_cents, total_cents, currency, payment_method, shipping_method, billing_address jsonb, shipping_address jsonb, notes, placed_at |
| `OrderItem` | order_id, product_id (nullable, history preserved via snapshot), name_snapshot, sku_snapshot, quantity, unit_price_cents, line_total_cents |
| `Payment` | order_id, gateway, gateway_ref, amount_cents, currency, status, raw_response jsonb |
| `Shipment` | order_id, carrier, tracking_number, label_url, status, raw_response jsonb |
| `SyncRun` | source, started_at, finished_at, feed_etag, feed_last_modified, items_seen, items_created, items_updated, items_deactivated, categories_created, manufacturers_created, status (running / succeeded / failed / skipped), errors_log jsonb |
| `Session` | user_id, ip_address, user_agent (Rails 8 auth scaffold) |
| `ActiveStorage::{Blob,Attachment,VariantRecord}` | standard, used by `ProductImage#file` once `ImageCacherJob` runs |

## Design system

Single source of truth for UI tokens and component patterns. **Every new view or partial MUST follow this — don't invent one-off colors / spacing / shadows.** Tied to Rule 10 (mobile-first) and Rule 11 (Czech-only).

### Brand colors (Tailwind palette)

| Token | Tailwind | Use |
|---|---|---|
| **Primary** | `rose-600` (default) / `rose-700` (hover) / `rose-800` (active) / `rose-50` (tint) / `rose-100` (subtle bg) / `rose-200` (border on hero) / `rose-300` (hover border) / `rose-500` (selected border) | All primary CTAs, links, current pagination page, active filter chips, focus rings (`focus:ring-rose-100`), brand accent in headlines |
| **Success / payment** | `emerald-50/100/500/600/700` | "Skladem" badges, payment-section selected state, paid-state pills, success flashes, gradient revenue cards |
| **Warning / pending / payment-instructions** | `amber-50/100/200/400/500/600/700/800` | Bank-transfer instructions callout, "Nejoblíbenější" badges (use emerald instead — see exception below), pending payment, payment-instructions on confirmation page |
| **Surface neutral** | `slate-50/100/200/300/400/500/600/700/800/900` | App background `bg-slate-100` (admin) / `bg-slate-50` (storefront), card borders `border-slate-200`, body text `text-slate-700`, muted `text-slate-500`, secondary buttons |
| **Error** | `rose-50/100/200/600/700/800` (same family as primary, the bg-rose-50 + text-rose-700 combo doubles as alert) | Validation errors, 404 fallback, destructive confirmations |

> Exception: status badges in admin use the wider palette (`amber` placed, `blue` processing, `indigo` shipped, `emerald` delivered, `rose` cancelled) — see `app/helpers/admin_helper.rb`.

### Typography

- Default font stack: system (Helvetica / Arial fallback) — Rails 8 default, no custom webfont.
- **Hero h1**: `text-3xl md:text-4xl lg:text-5xl font-bold leading-tight tracking-tight`
- **Page h1**: `text-2xl md:text-3xl font-bold`
- **Section h2**: `text-xl md:text-2xl font-bold` (`font-semibold` for narrower contexts)
- **Card / form-section h2**: `text-lg font-semibold`
- **Eyebrow / uppercase label**: `text-xs uppercase tracking-wide text-slate-500 font-semibold`
- **Body**: `text-base` minimum (≥ 16 px on mobile per Rule 10), `text-sm` only for secondary info
- **Code / monospace** (numbers, IBAN, SKU, order numbers): `font-mono`

### Spacing & radius

- **Container width**: `max-w-7xl mx-auto px-3 md:px-4` (storefront layout). Admin uses sidebar grid, no max-width.
- **Page vertical rhythm**: sections separated by `mt-6` / `mt-10` / `md:mt-12`. Cards inside a section: `space-y-5` / `space-y-6`.
- **Card padding**: `p-4 md:p-5` (compact), `p-5 md:p-6` (standard), `p-6 md:p-8` (auth/forms), `p-6 md:p-10` (hero).
- **Radius**: `rounded-xl` (small cards / inputs), `rounded-2xl` (standard cards / sections), `rounded-3xl` (hero / dark CTA bands), `rounded-full` (buttons, chips, indicators, pagination buttons).
- **Borders**: `border border-slate-200` (default card), `border-2 border-rose-100`/`border-emerald-100` (highlighted form section, see checkout).
- **Shadows**: `shadow-sm` (cards on hover), `shadow-lg shadow-rose-200` (primary CTA on hero), no big shadows in flat sections.

### Tap targets

Minimum **44 × 44 px** (WCAG 2.5.5). Standard sizes:
- **Primary CTA / submit**: `min-h-12` + `px-6 py-3` (~48 px tall)
- **Secondary button / pagination pill**: `min-h-10` + `px-4` or `w-10 h-10` (40 px — only above the 44 px floor when the visible target plus its padding exceeds 44 px)
- **Filter chips / facet rows**: `min-h-11`
- **Icon-only**: `w-11 h-11 inline-flex items-center justify-center`
- **Form inputs**: `min-h-12` + `px-4 py-3 text-base`

### Components & patterns (use these — don't invent variants)

#### Button — primary
```erb
<%= link_to "…", path, class: "inline-flex items-center justify-center gap-2 min-h-12 bg-rose-600 hover:bg-rose-700 active:bg-rose-800 text-white font-semibold rounded-full px-6 py-3 transition" %>
```

#### Button — secondary
```erb
<%= link_to "…", path, class: "inline-flex items-center justify-center gap-2 min-h-12 bg-white hover:bg-slate-50 border border-slate-200 rounded-full px-6 py-3 font-medium" %>
```

#### Button — destructive (icon-only)
```erb
<%= button_to path, method: :delete, class: "w-11 h-11 inline-flex items-center justify-center text-slate-400 hover:text-rose-600 hover:bg-rose-50 rounded-full" do %>
  <svg class="w-5 h-5" …>…</svg>
<% end %>
```

#### Form input
```erb
<input type="email" class="w-full min-h-12 pl-12 pr-4 py-3 border border-slate-200 rounded-lg text-base focus:border-rose-400 focus:ring-2 focus:ring-rose-100 outline-none">
```
With inline icon at `absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400 pointer-events-none`. **Always** set `autocomplete=` + appropriate `inputmode=` per Rule 10.

#### Card
```erb
<div class="bg-white border border-slate-200 rounded-2xl p-5 md:p-6">…</div>
```

#### Hero section
```erb
<section class="bg-gradient-to-br from-rose-100 via-white to-amber-50 rounded-3xl p-6 md:p-12 lg:p-16 overflow-hidden relative">…</section>
```
Add decorative blurred blobs: `<div class="absolute -top-20 -right-20 w-72 h-72 bg-rose-200/30 rounded-full blur-3xl pointer-events-none"></div>`.

#### Dark CTA band
`bg-gradient-to-br from-slate-900 via-slate-800 to-rose-900 text-white rounded-3xl p-6 md:p-12` — used for B2B / wholesale CTA only.

#### Chip (filter / facet / info)
- **Idle**: `inline-flex items-center min-h-9 bg-white border border-slate-200 hover:border-rose-300 rounded-full px-3 text-sm` + count `<span class="text-xs text-slate-400">`
- **Active**: `bg-rose-600 text-white border-rose-600`
- **Removable** (active filter): `bg-rose-50 text-rose-700 hover:bg-rose-100` + trailing `<span class="text-rose-400">×</span>`

#### Selectable card with hidden radio (checkout, etc.)
```erb
<label class="block relative cursor-pointer">
  <%= f.radio_button :method, "x", class: "peer sr-only" %>
  <div class="border-2 border-slate-200 rounded-2xl p-4 pr-10 transition
              hover:border-rose-300 hover:bg-rose-50/30
              peer-checked:border-rose-500 peer-checked:bg-rose-50 peer-checked:shadow-sm">…</div>
  <span aria-hidden="true" class="absolute top-3 right-3 w-6 h-6 rounded-full border-2 border-slate-300 bg-white peer-checked:border-rose-600 peer-checked:bg-rose-600 flex items-center justify-center">
    <svg class="w-3.5 h-3.5 text-white">…</svg>
  </span>
</label>
```
**Important**: peer-checked: only reaches *siblings* of the input. Indicator span MUST be a direct sibling of `<input class="peer">`, not nested inside the card div.

#### Numbered step header
```erb
<div class="flex items-center gap-3 mb-4">
  <span class="w-8 h-8 inline-flex items-center justify-center rounded-full bg-rose-600 text-white text-sm font-bold">3</span>
  <h2 class="font-semibold text-lg">Způsob dopravy</h2>
</div>
```

#### Mobile-first collapsible filter sidebar
```erb
<aside class="lg:sticky lg:top-20 lg:self-start">
  <details class="bg-white border border-slate-200 rounded-2xl lg:open" <%= "open" if has_filters %>>
    <summary class="flex items-center justify-between p-4 cursor-pointer list-none [&::-webkit-details-marker]:hidden lg:cursor-default">…</summary>
    <div class="px-4 pb-4 space-y-5 border-t border-slate-100 pt-4">…</div>
  </details>
</aside>
```
Always-open on `lg:`+, collapsed by default on phones unless filters are active.

#### Status / payment / shipping badge
Use the helpers in `app/helpers/admin_helper.rb`: `status_badge_class`, `payment_badge_class`, `sync_status_badge_class`. Rendered as `<span class="text-xs px-2.5 py-1 rounded-full <%= status_badge_class(o.status) %>">…</span>`.

#### Pagination
Always `<%= pagy_nav_pretty(@pagy) %>`. Never the raw `pagy_nav` (English numbers / no styling).

#### Pricing display
Always `format_price_cents(cents)` (helper) — never raw integer division. Czech format: `1 234,50 Kč` (space thousands, comma decimal, `Kč` after, space between).

#### Empty state
```erb
<div class="bg-white border border-slate-200 rounded-2xl p-8 md:p-12 text-center">
  <div class="text-4xl md:text-6xl mb-3">🔍</div>  <!-- emoji icon -->
  <h2 class="text-xl font-semibold mb-2">Nic jsme nenašli</h2>
  <p class="text-slate-500 mb-5 max-w-md mx-auto text-sm md:text-base">…</p>
  <%= link_to "CTA", path, class: "[primary button]" %>
</div>
```

### Iconography

- **Emoji** for category / section headers, illustrative use. Mapping (use these consistently across pages — don't drift): Kresba ✏️, Malba 🎨, Papírnictví 📄, Grafika 🖼️, Keramika 🏺, Tvoření ✂️, fallback 🎯.
- **Inline SVG** (24×24 viewBox, `stroke="currentColor"`, `stroke-width="2"` or `2.5` for bold strokes) for UI controls (search, lock, mail, cart, hamburger, checkmark, arrow). Never use a font-icon library.
- **Cart icon**: `<path d="M3 3h2l2 12h12l2-8H6"/><circle cx="9" cy="20" r="1.5"/><circle cx="17" cy="20" r="1.5"/>`
- **Search**: `<circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/>`
- **Lock**: `<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 018 0v4"/>`
- **Check**: `<path d="M5 12l5 5L20 7"/>` with `stroke-width="2.5"` or `3`
- **Hamburger**: `<path d="M4 6h16M4 12h16M4 18h16"/>`

### Animations

- `transition` (default) on hover/active state changes (border, bg, color, shadow).
- `animate-pulse` only on live-data signals (e.g. "Skladem 29k+" green dot).
- `group-hover:scale-105` on product images / category icons. **No fade-ins, no slide-ins on page load** — they hurt perceived performance.

### Responsive breakpoints (Tailwind defaults)

| Token | px | Use |
|---|---|---|
| (default) | < 640 | Phone — single column, full-width inputs, stacked CTAs |
| `sm:` | ≥ 640 | Big phones / small tablets — first chance to put two buttons side by side |
| `md:` | ≥ 768 | Tablets — flip tables ↔ cards, show 2-3 column product grids |
| `lg:` | ≥ 1024 | Laptops — sidebar layouts, sticky positioning, two-column heroes |
| `xl:` | ≥ 1280 | Wide desktops — 4-column product grid, larger paddings |

Single-column is the **default**. Per Rule 10, every new component must work at `< 640 px` first.

### Don't

- Don't add a new color outside the palette above (no `blue-500` for "info" — use `slate` or `rose` muted).
- Don't reach for a third-party UI kit (Bootstrap, DaisyUI, Tailwind UI components verbatim) — keep the bespoke Palkres look.
- Don't use icon font libraries (Font Awesome, Heroicons npm). Inline SVG only.
- Don't write CSS files — Tailwind utilities only. The single CSS file is `app/assets/tailwind/application.css` (just the `@import "tailwindcss"` directive).
- Don't add `font-family` overrides. System stack stays.
- Don't put more than two CTAs side by side on mobile — they truncate. Stack vertically.
- Don't ship a new component without `bin/rails assets:precompile` — new utility classes won't be in the built CSS.

## Key paths

### Code
| Resource | Path |
|---|---|
| App root | `/home/novakj/palkres-eshop/` |
| ARTIKON importer | `app/services/artikon/{feed_fetcher,feed_sax_handler,feed_importer}.rb` |
| Nightly + on-demand jobs | `app/jobs/artikon_sync_job.rb`, `app/jobs/image_cacher_job.rb` |
| Czech QR-platba (SPAYD) | `app/services/payments/czech_qr.rb` |
| Cart finder (session/user) | `app/services/cart_finder.rb` |
| Order mailer + views | `app/mailers/order_mailer.rb`, `app/views/order_mailer/confirmation.{html,text}.erb` |
| Storefront controllers | `app/controllers/storefront/{base,home,categories,products,search,cart,checkouts,order_confirmations}_controller.rb` |
| Storefront layout / views | `app/views/layouts/application.html.erb`, `app/views/storefront/**/*.erb` |
| Account area | `app/controllers/account/{base,orders,profiles}_controller.rb`, `app/views/account/**/*.erb` |
| Admin layout / nav / helper | `app/views/layouts/admin.html.erb`, `app/views/admin/shared/_nav_links.html.erb`, `app/helpers/admin_helper.rb` |
| Admin controllers | `app/controllers/admin/{base,dashboard,products,orders,sync_runs}_controller.rb` |
| Auth (Rails 8) | `app/controllers/{sessions,passwords}_controller.rb`, `app/controllers/concerns/authentication.rb` |
| Auth views (Czech) | `app/views/sessions/new.html.erb`, `app/views/passwords/{new,edit}.html.erb` |
| Pretty pagination helper | `app/helpers/application_helper.rb#pagy_nav_pretty` |
| Pricing init | `config/initializers/money.rb` |
| Pagination init | `config/initializers/pagy.rb` |

### Operations
| Resource | Path |
|---|---|
| Recurring jobs (cron) | `config/recurring.yml` (`artikon_nightly_sync` 0 3 * * *) |
| DB config | `config/database.yml` (reads `.env`) |
| Production env | `config/environments/production.rb` (SMTP wired off `SMTP_HOST` env) |
| Routes | `config/routes.rb` |
| Seeds (admin user) | `db/seeds.rb` |
| Systemd unit | `/etc/systemd/system/palkres-eshop.service` |
| Nginx site | `/etc/nginx/sites-available/palkres.techtools.cz` (HTTP→HTTPS redirect via certbot) |
| TLS certs | `/etc/letsencrypt/live/palkres.techtools.cz/` |
| Env file (gitignored) | `/home/novakj/palkres-eshop/.env` |
| Feed cache (gitignored) | `tmp/artikon/feed.xml` |
| ActiveStorage local files | `storage/` |

## Common commands

```bash
# Dev server (rails + tailwind watcher via foreman)
bin/dev

# Console
RAILS_ENV=development bin/rails console
RAILS_ENV=production  bin/rails console

# Manual ARTIKON sync (synchronous — useful for ops checks / first import)
RAILS_ENV=production bin/rails artikon:sync

# Trigger via the queue instead (matches the nightly path)
RAILS_ENV=production bin/rails runner 'ArtikonSyncJob.perform_later'

# Render the order-confirmation e-mail in console (no SMTP send)
RAILS_ENV=production bin/rails runner 'puts OrderMailer.confirmation(Order.last.id).body'

# Verify QR / IBAN config
RAILS_ENV=production bin/rails runner 'puts Payments::CzechQr.iban; puts Payments::CzechQr.placeholder?'

# Asset rebuild (REQUIRED after Tailwind class changes ship to prod)
RAILS_ENV=production bin/rails assets:precompile

# Migrations (always backup prod first)
RAILS_ENV=production pg_dump -U palkres -h 127.0.0.1 palkres_eshop_production \
  > /home/novakj/backups/palkres_$(date +%Y%m%d_%H%M%S).sql
RAILS_ENV=production bin/rails db:migrate

# Restart prod (puma + Solid Queue supervisor in one unit)
sudo systemctl restart palkres-eshop.service

# Tail prod logs
sudo journalctl -u palkres-eshop.service -f

# Issue / renew TLS (auto-renewal already wired via certbot timer)
sudo certbot renew --dry-run

# Background jobs (Solid Queue) standalone — only if not already running in Puma
bin/jobs

# Logs (production)
sudo journalctl -u palkres-eshop.service -f
```

## Post-launch change log

Newest at top. Every non-trivial production change should append an entry here.

### 2026-04-30 — Group-image URL: derive extension from the variant's IMAGE_BIG (was hardcoded .jpg → 404 on PNG families)
- **Bug**: `https://palkres.techtools.cz/produkt/cranfield-litho-ink-150ml-transparent-sun-64536` rendered no main image. The hero `<img src>` pointed at `https://www.artikon.cz/deploy/img/products/64516/64516.jpg` which returns **404** — Cranfield Litho Ink's family photo is `64516.png`, not `.jpg`. Same broken URL on every product whose variants use PNG (~4 578 variants in the catalog, ~15% — anything Cranfield-style with transparency).
- **Root cause**: yesterday's group-image change hardcoded `.jpg` as the extension when synthesizing the group URL. ARTIKON's group image actually preserves whatever extension the variants use (`<IMAGE_BIG>` returns `.jpg` for ~85% of products, `.png` for ~15%, a handful of `.gif`).
- **Fix**:
  - `Artikon::FeedImporter#map_item` now reads the extension off this SHOPITEM's own `IMAGE_BIG` (or `IMAGE`) URL and uses it when synthesizing the group URL. Whitelist of allowed extensions (`jpg|jpeg|png|gif|webp`); falls back to `jpg` if missing/unknown.
  - Backfill (one-shot SQL on prod + dev): derive each product's group extension from its `product_images.url` row's filename suffix and rewrite `group_image_url` accordingly. 29 257 rows updated in prod, 29 222 in dev.
- **Verified**:
  - Cranfield Litho Ink 150ml — Transparent: hero `<img src>` now points at `…/products/64516/64516.png` (HTTP 200), not `.jpg` (404).
  - Random sample of 10 families across the catalog: all 10 group-image URLs return 200 OK with real-sized images (12 KB – 188 KB) at the derived extension.
- **Files**: `app/services/artikon/feed_importer.rb`. `sudo systemctl restart palkres-eshop.service`. The DB column itself didn't need to change — only the value-derivation logic.

### 2026-04-30 — Fix bulk-add 500: items params is a Parameters hash, not a key-value pair list
- **Bug**: clicking "Vložit vybrané do košíku" with any selection raised `NoMethodError (undefined method '[]' for nil)` in `Storefront::CartController#bulk_add` and rendered the generic "We're sorry, but something went wrong" 500. Reproducible with the integration test below.
- **Root cause**: the form submits items as `items[0][product_id]=…&items[0][quantity]=…`. Rails parses this into `params[:items]` as `ActionController::Parameters` keyed by the index string ("0", "1", …), **not** as an array. The old code did `Array(params[:items]).map do |_idx, row|`. `Array(parameters_obj)` wraps the object as a single-element array (it doesn't iterate as `[[k,v],…]` like `Hash#to_a` does), so the destructuring assigned `_idx = parameters_obj` and `row = nil`, then `row[:product_id]` blew up.
- **Fix** (`app/controllers/storefront/cart_controller.rb`): iterate `params[:items].values` (which is supported on `ActionController::Parameters`) instead of relying on `Array()` + pair-destructuring. Also defensively `filter_map` so any non-Parameters entry is skipped:
  ```ruby
  raw_items = params[:items]
  rows = raw_items.respond_to?(:values) ? raw_items.values : Array(raw_items)
  entries = rows.filter_map do |row|
    next unless row.respond_to?(:[])
    { product_id: row[:product_id].to_i, quantity: row[:quantity].to_i }
  end
  ```
- **Verified**: integration test via `ActionDispatch::Integration::Session` with CSRF disabled — POSTed `items[0..2]` with quantities `0, 2, 3` → 303 redirect to `/kosik` → 200 with the "Přidáno do košíku" flash. Cleanup: cart row destroyed.
- **Files**: `app/controllers/storefront/cart_controller.rb`. `sudo systemctl restart palkres-eshop.service`.

### 2026-04-30 — "Vložit vybrané do košíku" promoted to a floating action panel
- **Why**: variant-picker bar was `sticky bottom-0` *inside* the variant section, so once the customer scrolled past the section (e.g. to read description, related products, or to scroll a 472-row paint family from row 1 toward the top), the CTA disappeared. The action button needs to be reachable from anywhere on the product page.
- **Fix** (`app/views/storefront/products/show.html.erb`):
  - Replaced the section-scoped `sticky` element with a viewport-fixed panel.
  - **Mobile** (`<md`): full-width bar pinned to `bottom-0` of the viewport (`fixed inset-x-0 bottom-0`), white background + top border + drop shadow.
  - **Desktop** (`md:`+): floating compact card in the bottom-right corner (`md:right-6 md:bottom-6 md:w-[22rem] md:rounded-2xl md:shadow-rose-200/40`), so it doesn't block reading the description column on the left.
  - Added a `h-36 md:h-6` spacer above the fixed bar so the last variant row isn't hidden behind it on mobile.
  - Submit button is now `w-full` inside the card; the "Vybráno X ks · Cena Y Kč" line stacks above on both breakpoints (no md:flex-row).
  - `data-variant-picker-target` hooks (`total`, `totalPrice`, `submit`) unchanged — the existing Stimulus controller (`variant_picker_controller.js`) updates them as before, regardless of where the elements live in the DOM.
- **Verified**: live page emits `<div class="fixed inset-x-0 bottom-0 z-40 …">` containing the button. Variant grid above keeps its row layout; spacer prevents overlap with the last row.
- **Files**: `app/views/storefront/products/show.html.erb`. `bin/rails assets:precompile` + `sudo systemctl restart palkres-eshop.service`.

### 2026-04-30 — Product vs. variant images: family card / hero now uses ITEMGROUP_ID photo
- **Bug**: e.g. `/produkt/kridove-barvy-ambiente-250ml-milano-4-sun-2173` rendered a **60×24 / 408-byte placeholder** as the main product photo; same on the chalk-paint family's listing card. Across the catalog, many ARTIKON variants (per-color paint, per-size brush) ship with a placeholder JPEG at their per-variant `IMAGE_BIG` URL because the supplier doesn't have a per-variant photo — but the family/group photo at `https://www.artikon.cz/deploy/img/products/<ITEMGROUP_ID>/<ITEMGROUP_ID>.jpg` IS a real picture (18 KB for 2168.jpg in this case). We were storing only the per-variant URL, so listings + product hero showed the placeholder.
- **Root cause**: ARTIKON's data model has TWO image levels (per-variant + per-group) but the feed XML only emits the per-variant `<IMAGE>`/`<IMAGE_BIG>`. The per-group image is implicit — accessible at the URL convention `/deploy/img/products/<ITEMGROUP_ID>/<ITEMGROUP_ID>.jpg`. Importer was ignoring the group level entirely.
- **Fix — split product image (group/family) from variant image (per SKU)**:
  - Migration `add_group_image_url_to_products` adds `products.group_image_url` (string).
  - `Artikon::FeedImporter#map_item` now derives `group_image_url` from `ITEMGROUP_ID` using the URL convention (only when numeric — guards `\A\d+\z` so we don't write garbage for non-numeric group IDs).
  - `Product#variant_image_url` (alias for `primary_image_url`) — the SHOPITEM's own per-variant photo. Still stored on `product_images`.
  - `Product#family_image_url` — `group_image_url.presence || primary_image_url`. Used wherever we want the **product** picture rather than a specific variant.
  - Listing card (`_card.html.erb`): family-collapsed cards (`has_variants`) now render `product.family_image_url`. Singletons unchanged (`primary_image_url`).
  - Product detail hero (`products/show.html.erb`): when the product has variants, the big square shows `family_image_url` (the group photo) and a small **"Tato varianta"** thumbnail row underneath shows the per-variant `variant_image_url` so the customer can still see which color/size they landed on. Singletons still show their own image as the only hero.
  - Variant grid (`#varianty` section) is **unchanged** — each row still shows its own `primary_image_url`. The user explicitly wanted "variant should have variant picture", so per-variant placeholders here are the correct, supplier-truthful behavior.
  - Home page collage: `family_image_url` (recent products are family-collapsed there, same as listings).
- **Backfill**: `Product.where("item_group_id ~ '^[0-9]+$'").update_all("group_image_url = 'https://…/products/' || item_group_id || '/' || item_group_id || '.jpg'")` — 29 257 rows in prod, 29 222 in dev. Future imports populate via the importer change above.
- **Verified**:
  - `https://palkres.techtools.cz/produkt/kridove-barvy-ambiente-250ml-milano-4-sun-2173` hero now sources `https://www.artikon.cz/deploy/img/products/2168/2168.jpg` (18 367 bytes — the real chalk-paint family photo). The "Tato varianta" thumb still points at `2173/2173.jpg` (the placeholder), which is correct since ARTIKON has no per-color photo for this paint.
  - Category listing `/kategorie/tvoreni/dekorovani-nabytku/kridove-barvy` now renders `2168/2168.jpg` for the chalk-paint family card (was rendering `2173/2173.jpg` placeholder before).
  - Singletons (e.g. Stabilo Woody sharpener Sun-67113) still render their own `67113/67113.jpg` (real 71 KB image), unchanged.
- **Files**: `db/migrate/20260430135044_add_group_image_url_to_products.rb`, `app/services/artikon/feed_importer.rb`, `app/models/product.rb`, `app/views/storefront/products/_card.html.erb`, `app/views/storefront/products/show.html.erb`, `app/views/storefront/home/show.html.erb`. `bin/rails assets:precompile` run; `palkres-eshop.service` restarted.
- **Gotcha for future**: ARTIKON variant images that come back ~400 bytes (`60×24` JPEG with a `{"s":"…","x":"60","y":"60"}` JFIF comment) are placeholders. We now sidestep them on family/listing/hero contexts by preferring the group image; if we ever want the variant grid to also fall back, we'd need a placeholder probe (size HEAD or hash compare) — punt for now since per-variant placeholders are still supplier-accurate.

### 2026-04-30 — Source feed promoted to top-level CRITICAL section in CLAUDE.md
- Added a 🔴 **CRITICAL — Source of truth: ARTIKON XML feed** section right after the file title. Spells out the canonical URL (`https://www.artikon.cz/feeds/xml/VO_XML_Feed_Komplet_2.xml`), feed size (~163 MB / ~29 222 SHOPITEMs), local cache (`tmp/artikon/feed.xml`, gitignored), the per-variant vs. group-level image convention, and a pointer to Rule 5 (SAX-only) + the three importer files in `app/services/artikon/`. Why: the URL was previously buried as a single bullet in **At-a-glance**, easy to miss; the feed is the only source of truth for catalog state and any image / pricing / stock investigation must start by re-reading it.

### 2026-04-29 — Listings collapse variants into one card per `item_group_id`
- **Why**: ARTIKON puts every color / size variant into the catalog as a separate product (e.g. 525 entries for one Sennelier pastel family, 472 for Umton oil paint). Listings were showing each variant as its own card → 29 250 cards across the catalog, the same family fills entire pages, search for "stabilo" returned 205 hits, and the "Do košíku" button on a card added a specific arbitrary color rather than letting the customer pick. The product page already has the variant-bulk-add UX (2026-04-25); listings should funnel to it instead of duplicating it.
- **What changed (user-visible)**:
  - Category, search, and home listings now show **one card per family**. The card displays the family name (e.g. "Olejová barva Renesans 20ml" instead of "Olejová barva Renesans 20ml – 41 zeleň hooker"), a rose **"X variant"** badge in the top-right corner of the image, and an **"od " prefix on the price** (since the displayed price is the cheapest variant in the family).
  - The CTA on multi-variant cards changed from "Do košíku" to **"Vybrat →"** that scrolls to `#varianty` on the product page (the existing variant-picker grid). Singletons keep "Do košíku" exactly as before.
  - Counts everywhere now reflect families: search "stabilo" → **32 families** (was 205), Novinky → **108 produktů** (was 418), manufacturer facets count families too. Total catalog drops from 29 250 cards to 7 637.
- **Implementation**:
  - `Product::GROUP_KEY_SQL` (`app/models/product.rb`) — Postgres `COALESCE(item_group_id, 'p-' || id::text)` so ungrouped products are still their own group.
  - `Product.one_per_variant_group_of(scope)` — wraps any caller scope in a `WHERE id IN (SELECT DISTINCT ON (group_key) id … ORDER BY group_key, price_retail_cents ASC NULLS LAST, id)` subquery. Cheapest active variant becomes the representative; ties broken by id. **Must `unscope(:order, :limit, :offset).distinct(false)` on the inner scope** — see gotcha below.
  - `Product.variant_counts_for(products)` — single follow-up query keyed on `item_group_id`, returns `{ group_id => count }` for the page being rendered.
  - `Storefront::CategoriesController#show` and `Storefront::SearchController#show` now run their existing filtered `base` scope through `Product.one_per_variant_group_of(base)` before `pagy(...)`, build `@variant_counts`, and apply manufacturer facets / totals to the grouped scope.
  - `Storefront::HomeController#show` collapses `@recent_products`, `@best_deals`, and `@stats[:products]` the same way.
  - `_grid_with_load_more.html.erb` and `home/show.html.erb` forward `variant_counts` as a local to the `_card` collection render.
  - `_card.html.erb` reads `local_assigns[:variant_counts]`, computes `has_variants` (count > 1), swaps title to `variant_family_name`, prefixes price with "od ", renders the badge, and switches the CTA to a `#varianty` link. Safely defaults to old behaviour when no `variant_counts` local is passed (any future caller of the partial).
- **Gotchas**:
  - The category controller chains `.distinct` onto `base`. Plain `where(id: subquery)` produced `SELECT DISTINCT DISTINCT ON (...)` → Postgres syntax error. Fix: `scope.unscope(:order, :limit, :offset).distinct(false).select(Arel.sql("DISTINCT ON (...) products.id"))` so the inner subquery owns the DISTINCT.
  - The outer query on the new scope is a **fresh** `Product.where(id: …)` — no joins from the input scope leak through. That means user-facing `ORDER BY` (e.g. `price_retail_cents ASC`) applies cleanly without conflicting with `DISTINCT ON`'s required leading sort.
  - The picked representative is the *cheapest* variant. When the user sorts by `price_asc`, the displayed prices match the sort order (no surprise of "the family's cheapest variant is shown but the family has a more-expensive rep here").
- **Verified**:
  - Console: `Product.active.where("price_retail_cents > 0").count` = 29 250 → `one_per_variant_group_of(...).count` = 7 637.
  - Search "stabilo": 205 variants → 32 families. Manufacturer facets are per family.
  - Category Novinky: 418 variants → 108 families. Top family "Akrylová barva Kreul Matt :: 48 variant" (one card, badge "48 variant", "Vybrat →" CTA visible in HTML).
  - Curl smoke 200s on `/`, `/hledat?q=stabilo`, `/kategorie/novinky`, `/kategorie/novinky?in_stock=1&per_page=48&sort=price_asc`.
  - HTML inspection on Novinky: badge "48 variant", "Vybrat →" link to `…#varianty`, `<strong>108</strong> produktů` headline.
  - `bin/rails assets:precompile` ran (new `whitespace-nowrap` is already in default Tailwind, but the CSS was rebuilt for safety).
- **Files**: `app/models/product.rb`, `app/controllers/storefront/categories_controller.rb`, `app/controllers/storefront/search_controller.rb`, `app/controllers/storefront/home_controller.rb`, `app/views/storefront/products/_card.html.erb`, `app/views/storefront/products/_grid_with_load_more.html.erb`, `app/views/storefront/categories/show.html.erb`, `app/views/storefront/search/show.html.erb`, `app/views/storefront/home/show.html.erb`.

### 2026-04-25 — Variant bulk-add + per-page + load-more + filters open by default
- **Why**: paint products with many color/size variants need a single page where the customer marks quantities for several variants and adds them to the cart in one click; listing pages need a per-page selector and a "load more" mechanism so the previous page stays visible while continuing; filters sidebar should be **expanded by default** on every breakpoint (not collapsed on mobile / only-open-when-active).
- **What changed (user-visible)**:
  - Product detail page (`/produkt/:slug`) now shows a "Vyberte varianty" section listing every product in the same `item_group_id`. Each row has a thumbnail, color/size label, price, stock indicator and a [−][n][+] qty stepper. A sticky footer shows live "Vybráno: X ks · Cena celkem: Y Kč" and a single "Vložit vybrané do košíku" button posts the whole batch in one request. Family name (e.g. "Kulatý štětec Master 1006R") is extracted by splitting on the en-dash so the page heading reads cleanly.
  - Category and search listings now have a "Na stránku: 24 / 48 / 96" selector next to the sort dropdown.
  - Below the grid is a "Načíst další produkty" button that fetches the next page and **appends** to the current grid without losing the items already shown. Numbered pagination is still rendered below for jump-to-page.
  - Filters sidebar (`<details>`) is now **always expanded by default** on every breakpoint (was: collapsed on mobile, only auto-open when filters were active) so the filter chips/checkboxes are visible without an extra tap.
- **Implementation**:
  - `Cart#add_many(entries)` (`app/models/cart.rb`): transactional bulk add; quantities ≤ 0 are skipped; reuses `add_product` so existing-cart-item increment semantics are preserved.
  - New route `POST /kosik/pridat-hromadne` → `Storefront::CartController#bulk_add` (`config/routes.rb`, `app/controllers/storefront/cart_controller.rb`). Reads `params[:items]` (a hash keyed by index), filters to integers, redirects to /kosik with a Czech flash count.
  - `Product#variants` / `#has_variants?` / `#variant_label` / `#variant_family_name` (`app/models/product.rb`): scoped to same `item_group_id` and `price_retail_cents > 0`; label/family extraction splits the product name on `\s+[–—-]\s+`.
  - `Storefront::ProductsController#show` eagerly loads `@variants.includes(:manufacturer, :product_images).order(:name)` only when the product has siblings.
  - View `app/views/storefront/products/show.html.erb` rewritten: hero + main pane unchanged; new `<section id="varianty">` with the bulk-add form, mobile-first row layout (image/title/price/stepper stack on phones, align horizontally at md:+), sticky footer with the running totals.
  - New Stimulus controller `app/javascript/controllers/variant_picker_controller.js`: targets `qty`, `total`, `totalPrice`, `submit`, `rowTotal`. Recalcs on `input`/`change`, supports +/− buttons, formats prices in Czech style (space thousand separator, comma decimal, "Kč" suffix), disables the submit button until at least one variant has a quantity, highlights non-zero rows with a rose tint.
  - Pagination per-page: `Storefront::CategoriesController` and `Storefront::SearchController` accept `params[:per_page]` whitelisted to `[24, 48, 96]` (default 24) and pass it to `pagy(scope, limit: @per_page)`.
  - Shared partial `app/views/storefront/products/_grid_with_load_more.html.erb`: wraps `#products-grid` and `#load-more-wrapper` (the IDs the Stimulus controller targets), renders the next-page link if `@pagy.next`, then `pagy_nav_pretty` underneath.
  - New Stimulus controller `app/javascript/controllers/load_more_controller.js`: on click of the "Načíst další" link, fetches the next page URL (Accept: text/html), parses with DOMParser, appends the children of the response's `#products-grid` into the current one, then replaces `#load-more-wrapper` with the response's. Updates `history.replaceState` so refresh keeps you on the loaded page. Works with all current filters (manufacturer / in_stock / sort / per_page) since the link href is built from `request.query_parameters.merge(page: @pagy.next)`.
  - Both category and search views got the per-page selector form alongside the existing sort form.
  - Filters-open-by-default: the `<details class="… lg:open">` element in `app/views/storefront/categories/show.html.erb` and `app/views/storefront/search/show.html.erb` had its conditional `<%= "open" if has_filters %>` replaced with an unconditional `open` attribute, so the dropdown is expanded the moment the page loads regardless of breakpoint or filter state.
- **Verified**:
  - Smoke 200s on `/`, `/hledat`, `/hledat?q=stabilo&per_page=48`, `/kosik`, `/kategorie/.../novinky`, `/kategorie/.../novinky?per_page=96`, the unknown `per_page=999` (clamps silently to 24).
  - `Cart#add_many` console test: 5 entries (qty 1,2,3,4,0) → 4 items added, qty sum 10, prices snapshotted from `price_retail_cents`. Zero quantities correctly skipped.
  - Variant page on a 16-variant brush family renders 16 hidden `items[i][product_id]`, 16 `items[i][quantity]` inputs, 16 `data-unit-cents`, form action `/kosik/pridat-hromadne`, family heading "Kulatý štětec Master 1006R" (suffix stripped).
  - Variant page on the 472-variant Umton oil paint family loads in ~0.4 s, 1.3 MB HTML — acceptable; all 472 rows render. (If perf becomes an issue we can paginate the variant grid by size or color, but the customer asked for the whole list, so keep it for now.)
  - Category load-more wrapper renders an `<a href="/kategorie/...?in_stock=1&page=2&per_page=24">` — filters preserved.
  - Selected `per_page` option is `selected="selected"` in the dropdown.
  - After the filters-open-by-default change: re-curled `/kategorie/.../novinky` and `/hledat?q=stabilo` and confirmed the rendered HTML now contains `<details class="… lg:open" open>` on a clean URL (no filters applied) — the panel renders expanded.
- **Files**: `app/models/cart.rb`, `app/models/product.rb`, `app/controllers/storefront/cart_controller.rb`, `app/controllers/storefront/products_controller.rb`, `app/controllers/storefront/categories_controller.rb`, `app/controllers/storefront/search_controller.rb`, `config/routes.rb`, `app/views/storefront/products/show.html.erb`, `app/views/storefront/products/_grid_with_load_more.html.erb` (new), `app/views/storefront/categories/show.html.erb`, `app/views/storefront/search/show.html.erb`, `app/javascript/controllers/variant_picker_controller.js` (new), `app/javascript/controllers/load_more_controller.js` (new). `bin/rails assets:precompile` ran (Tailwind 4.2 + new Stimulus controllers fingerprinted).

### 2026-04-25 — Category page redesign + Design System section in CLAUDE.md
- **Category page redesign** (`app/views/storefront/categories/show.html.erb`, `app/controllers/storefront/categories_controller.rb`):
  - **Hero header** with category emoji (mapped: Kresba ✏️ / Malba 🎨 / Papírnictví 📄 / Grafika 🖼️ / Keramika 🏺 / Tvoření ✂️), title + subtitle showing `"X produktů v Y podkategoriích"`. Same gradient as the home hero (`from-rose-50 via-white to-amber-50`).
  - **Subcategory chips** as a flex-wrap row above the grid: each chip shows name + product count, linked, mobile-friendly 44 px tap targets (was a plain `<ul>` left-aligned in the sidebar).
  - **Sticky filter sidebar** that collapses into a `<details>` drawer on mobile, always-open on `lg:`+. Same component pattern as the search page — "Pouze skladem" toggle + manufacturer facet with counts (top-20 by product count).
  - **Sort + active-filter chips bar** above the grid (mirrors search page UX): result count, removable chips for selected manufacturer / in-stock, sort dropdown (Název A–Z / Z–A, Cena nejnižší / nejvyšší, Nejnovější).
  - Controller now hardens sort against arbitrary input (`SORTS` whitelist), wraps the manufacturer-facet `COUNT(DISTINCT)` in `Arel.sql` to silence Rails 8's `UnknownAttributeReference` raw-SQL guard, and exposes `@total_in_category`, `@selected_manufacturer`, `@manufacturer_facets` for the new chips.
  - Pagination already uses `pagy_nav_pretty` (no change).
- **New "Design system" section in CLAUDE.md** (between Data model and Key paths): canonical reference for tokens + components.
  - Brand colors (`rose` primary / `emerald` success / `amber` warm / `slate` neutral) with each shade's role
  - Typography scale (`text-3xl md:text-4xl lg:text-5xl` hero down to `text-xs uppercase tracking-wide` eyebrow)
  - Spacing & radius (`rounded-xl/2xl/3xl/full`, padding scale per surface), shadows
  - Tap-target floor (44 px) + standard button heights
  - Component snippets to copy-paste: primary/secondary button, form input + inline icon, card, hero, dark CTA band, chip (idle/active/removable), peer-checked selectable card with the indicator-must-be-sibling rule, numbered step header, mobile-first collapsible `<details>` filter sidebar, status badge helpers, pretty pagination, price formatter, empty state
  - Iconography: emoji map for categories + inline-SVG snippets for cart / search / lock / check / hamburger
  - Animation rules: `transition` always, `animate-pulse` only for live signals, no on-load fade/slide
  - Responsive breakpoint table (sm/md/lg/xl) with what each tier should add
  - Hard "Don't" list: no third-party UI kits, no icon fonts, no extra color tokens, no CSS files (Tailwind utilities only), no `font-family` override, no skipping `assets:precompile` after class changes
- The Design System makes Rule 10 (mobile-first) and Rule 11 (Czech-only) actionable: any new view should now copy a snippet from this section instead of inventing one-off styles. Future divergence is a code-review concern.

### 2026-04-25 — Home page conversion redesign
- Old home: 4-block hero + flat category list + recent products + plain brand chips. No social proof, no reasons-to-buy, no big-ticket CTA, no funnel for B2B/wholesale.
- New home (`app/views/storefront/home/show.html.erb` + `app/controllers/storefront/home_controller.rb`):
  - **Hero**: live "Skladem 29 000+ produktů" pulse-dot pill, double-line headline with rose accent, dual CTA ("Prohlédnout katalog" + "Hledat produkt"), three trust microcopy (doručení 1–2 dny / bezpečná platba / 14 dní na vrácení), staggered 4-product image collage (right), decorative blurred blobs.
  - **Trust strip**: 4 white cards with emoji icons (🚚 / 💳 / 🔄 / 🎨) — rychlé dodání, platba kartou i QR, 14denní vrácení, kvalitní značky.
  - **Hlavní kategorie**: visual grid with per-category gradient backgrounds (rose, amber, emerald, sky, violet, pink) and emoji icons matched to category name (`/kresb/` → ✏️, `/malb/` → 🎨, etc.); bigger tap targets (`min-h-32`/`md:min-h-36`), hover scale on icon.
  - **Novinky v sortimentu**: 8-product grid (was 12) with "Vše →" link to search.
  - **Big CTA band** (slate→rose gradient, white text, decorative blob): "Velkoodběry & dealer ceny" pitch for B2B/schools, 4-bullet checklist (5 000 Kč threshold, individuální splatnost, personální podpora, 29 000 položek), two CTA buttons (mailto + browse catalog) — first conversion path beyond a single-customer purchase.
  - **Brands**: chips now link directly to `search_path(q: brand_name)` so clicking Stabilo opens search results filtered to that manufacturer.
  - **Stats footer**: 3 large rose numbers — products / categories / manufacturers — pulled live from new controller `@stats`.
- Controller: added `@best_deals` scope (reserved for a future sale ribbon), `@stats` for the footer counters.
- All copy Czech per Rule 11; mobile-first per Rule 10 (every section stacks vertically, hero CTAs become full-width on small screens, image collage drops the staggered offset).
- `bin/rails assets:precompile` to ship new utilities (gradient utility variants, animate-pulse).

### 2026-04-25 — Documentation audit (this entry)
- Refreshed the structured sections so they reflect everything that landed today and is in git (`cdc24f3` → `ccf92bb`):
  - **At-a-glance**: added GitHub repo SSH URL, live URL + TLS expiry, admin login + rotation command, the techtools IBAN currently used for QR-platba, and SMTP-not-yet-configured note. Listed all 7 production DBs (primary + 3 Solid).
  - **Data model**: `Order` row now lists `confirmation_token`, `email`, `phone`, all three enums (status / payment_state / shipping_state) with their prefixes, `payment_method`, `shipping_method`, `billing/shipping_address jsonb`, `placed_at`. `Category` has `ancestry_depth` + `products_count`. `ProductImage` notes the `cached` bool + `has_one_attached :file`. `Address` lists every column. Added `Session` row (Rails 8 auth). Added the three `ActiveStorage::*` tables.
  - **Key paths**: split into "Code" (every services/jobs/mailer/helper/controller path that exists) and "Operations" (cron / nginx / TLS / env / cache).
  - **Common commands**: added e-mail-rendering check, QR-config check, asset precompile (with the "REQUIRED after Tailwind class changes ship to prod" note that bit us once), pg_dump + migrate combo, certbot renewal dry-run.
- No code change, just documentation. The change-log entries above are already complete; this audit only updates the structured sections that future-you and future-Claude will read first.

### 2026-04-25 — Login + password-reset views (Czech, mobile-first) + Rule 11 (Czech-only)
- Replaced the Rails 8 generator's English `sessions/new`, `passwords/new`, `passwords/edit` with Czech, brand-styled views: card form on the left, gradient brand panel on the right (lg:+ only) with "Výtvarné potřeby pro radost z tvorby" + 3 benefit bullets. Inline icons on inputs (mail/lock SVGs), `min-h-12` tap targets, focus rose ring, "Zapomenuté heslo?" link inline with the Heslo label, autocompletes (`username` / `current-password` / `new-password`).
- All copy translated: "Přihlášení", "Přihlásit se", "Zapomenuté heslo", "Poslat instrukce", "Nastavte si nové heslo", "Uložit nové heslo", "Zpět na přihlášení", placeholder `vase@adresa.cz`, password "alespoň 10 znaků".
- Bug discovered while testing: a Write to `sessions/new.html.erb` was silently rejected by the harness because the file hadn't been Read in this session yet — the smoke test still showed Czech only because the application layout's header link "Přihlášení" was leaking into the grep. Fixed by re-Reading then Writing.
- **New Rule 11 in Critical project rules**: "The whole app is in Czech — every user-facing string MUST be in Czech." Lists English-creep traps (Rails scaffolds, validation messages, `strftime %A`, money formatting, enum.humanize), the only acceptable English (code identifiers, wire-format keys, `lang="cs"`), and a pre-merge grep recipe. The previous Rule 11 (document-every-change) renumbered to Rule 12.

### 2026-04-25 — Admin redesign + slug-lookup 404 fix
- **Bug**: `/admin/products/<slug>` returned 404 because `Admin::ProductsController#show` (and `#update`) used `Product.find(params[:id])` instead of `Product.friendly.find`. The index links to slugged URLs but the action couldn't resolve them.
- **Fix** (`app/controllers/admin/products_controller.rb`, `…/orders_controller.rb`): use `friendly.find` for products. Added filter chips (Vše/Aktivní/Neaktivní/Top sellers/Vyprodáno/Bez obrázku) + manufacturer dropdown + extended search (name/SKU/ARTIKON ID/EAN). Counts are pre-computed and shown on the chips.
- **Layout** (`app/views/layouts/admin.html.erb` + `app/views/admin/shared/_nav_links.html.erb`): mobile top bar with hamburger `<details>` menu, sticky 240 px sidebar on `lg:`+, current page highlighted in rose, "Přejít na e-shop" + "Odhlásit" pinned at the bottom of the nav. Logged-in user shown in the sidebar footer.
- **Dashboard** (`app/controllers/admin/dashboard_controller.rb`, `app/views/admin/dashboard/show.html.erb`): four KPI cards (Produkty / Top sellers / Bez obrázku / Nové objednávky) clickable to filtered lists; two gradient revenue cards (paid + pending); two-column "Poslední objednávky" + "ARTIKON feed" sections.
- **Products list**: thumbnail + name/SKU/manufacturer/stock/price/active-dot/topseller-star, table on `md:`+ collapsing to clean stacked cards on phones, big primary search field with magnifier icon, mobile-friendly filter chips that scroll horizontally if they overflow.
- **Product show**: 280 px image + thumbnails sidebar with "Rychlé akce" inline form (toggle aktivní / topseller, save), and a main pane with header chips, ARTIKON ID / SKU / EAN / Sklad / Hmotnost / synced-at, three-card pricing block (S DPH / Bez DPH / Dealer), categories chips that link to the public storefront, sanitized description block. Footer buttons: "Otevřít na ARTIKON" + "Otevřít v e-shopu".
- **Orders list**: same chip-pattern filters by status (Vše / Nové / Zpracování / Odeslané / Doručené / Zrušené) with counts, tržby paid total in subtitle, table → cards on mobile, status + payment colored badges via new `AdminHelper#status_badge_class` / `payment_badge_class`.
- **Order show**: header with order number + status/payment chips, items section with snapshot lines + totals, billing/shipping address cards, optional yellow "Poznámka zákazníka" callout, sticky right sidebar with customer info + shipping/payment method + status-change form + a "↗ Otevřít zákazníkovu stránku potvrzení" button that opens the public confirmation URL with token.
- **Helper module**: new `app/helpers/admin_helper.rb` with badge-class lookups.
- **Asset rebuild**: `bin/rails assets:precompile` to ship new utilities.
- Verified end-to-end: logged in as `admin@palkres.cz`, all 5 admin routes return 200 including the previously-404 slug URL `/admin/products/olejova-barva-renesans-20ml-41-zelen-hooker-sun-1365`. Content snippets present: "Rychlé akce", "ARTIKON ID", "Ceny", "Kategorie".

### 2026-04-25 — Real bank account wired into QR-platba
- Earlier change-log claimed the IBAN was a placeholder. Replaced with the real account from `.env`. IBAN check digits computed via ISO 13616 (`98 − ((bank ‖ prefix ‖ account ‖ encoded(country) ‖ 00) mod 97)`).
- `Payments::CzechQr` gains `placeholder?` predicate; `available?` now also returns false when IBAN is one of the known placeholders, so the QR + SPAYD block won't render with a fake account if the env ever gets reverted.
- Sample SPAYD format verified: `SPD*1.0*ACC:<IBAN>*AM:<amount>*CC:CZK*X-VS:<vs>*MSG:<msg>*RN:<name>`.

### 2026-04-25 — Checkout: Doprava + Platba split into separate sections
- Old UX: shipping + payment options were mixed in a single 2-column grid under one "Doprava a platba" heading. Looked like 4 mutually-exclusive options instead of "pick one shipping AND one payment".
- New UX (`app/views/storefront/checkouts/show.html.erb`): five numbered steps (Kontakt 1, Fakturační adresa 2, Způsob dopravy 3, Způsob platby 4, Poznámka 5) with rose number badges. Sections 3 and 4 are visually distinct: step 3 has rose-100 outline + rose number badge, step 4 has emerald-100 outline + emerald number badge — so the eye instantly groups them as separate decisions.
- Each option is a big card: large emoji icon, title + colored selected-state badge ("Nejoblíbenější", "Bez poplatků", "Okamžitě"), subtitle, price (shipping) or detailed description (payment). Selected state: 2-px colored border, tinted background (`bg-rose-50` / `bg-emerald-50`), shadow, and a filled circular checkmark indicator in the top-right corner.
- Selected-state CSS via Tailwind `peer:`/`peer-checked:` variants only — no JS. The hidden radio (`peer sr-only`) is a sibling of both the card `<div>` and the indicator `<span>`, so the checkmark uses `peer-checked:bg-rose-600 peer-checked:border-rose-600` directly. (Earlier attempt used `peer-checked:group-[]:` for a nested SVG and didn't work — peer variants only reach siblings.)
- Inputs got mobile improvements too: `min-h-12`, proper `autocomplete=` (email/tel/given-name/…), `inputmode=` for numeric fields, focus rose ring; required-asterisk markers preserved.
- Submit button: full-width rose pill 48 px tall with "Stisknutím potvrzujete závaznou objednávku" subtitle.

### 2026-04-25 — Confirmation e-mail + Czech QR-platba (SPAYD)
- New `Payments::CzechQr` service (`app/services/payments/czech_qr.rb`) builds a SPAYD-1.0 payload (`SPD*1.0*ACC:<IBAN>*AM:…*CC:CZK*X-VS:…*MSG:…*RN:Palkres s.r.o.`) and renders an inline SVG via `rqrcode 3.0`. Standard scannable by Air Bank, ČS, KB, Raiffeisen, Fio etc.
- Bank account configured via `.env`: `PALKRES_BANK_IBAN` (default `CZ6508000000192000145399` placeholder — **swap before going live with real Palkres IBAN**), `PALKRES_BANK_NAME`. `Payments::CzechQr.available?` guards against missing/invalid IBAN.
- New `OrderMailer#confirmation(order_id)` (`app/mailers/order_mailer.rb`):
  - Subject: `Potvrzení objednávky PK-… — Palkres`
  - HTML + plain-text multipart layouts; QR SVG attached inline (`cid:payment-qr.svg`) for `bank_transfer` orders only
  - Bcc copy to `ORDER_MAIL_BCC` (`info@palkres.cz` by default) so Palkres has the order in their inbox
  - Reply-To set so customer replies go to `info@palkres.cz`, not the no-reply sender
  - Renders the same status hero, line items, totals, addresses, and a tracking link to the public confirmation URL with token
- `ApplicationMailer` now includes `helper ApplicationHelper` (mailers don't auto-pull view helpers; `format_price_cents` was undefined before).
- Production SMTP wired in `config/environments/production.rb`: `delivery_method: :smtp` when `SMTP_HOST` is set (env vars `SMTP_HOST/PORT/USER/PASS/DOMAIN`); falls back to `:test` (no real send) when SMTP isn't configured. `default_url_options` reads `APP_HOST` so links in mail point at `https://palkres.techtools.cz/objednavka/…?token=…`.
- `Storefront::CheckoutsController#create` now does `OrderMailer.confirmation(order.id).deliver_later` after wiping the cart. Goes through Solid Queue so checkout response is fast.
- The on-page confirmation now also embeds the QR + payment details (IBAN, VS, amount, message) in an amber callout for `bank_transfer` orders. Mobile-friendly: stacks vertically on phones.
- Verified end-to-end: SPAYD generated, mail rendered (HTML 7.7 KB, text 0.9 KB), inline SVG attached, BCC set, confirmation page now shows QR (`naskenujte QR`, IBAN, VS).

**Operational TODO**: when Palkres provides real SMTP credentials, set `SMTP_HOST/PORT/USER/PASS/DOMAIN` in `/home/novakj/palkres-eshop/.env` and `sudo systemctl restart palkres-eshop.service`. Until then, mail "delivers" to `:test` (visible in `ActionMailer::Base.deliveries` in console, not actually sent).

### 2026-04-25 — Order confirmation / status page after checkout
- Old behaviour: `Storefront::CheckoutsController#create` redirected to `account_order_path(order)`, which requires login. Guest checkout therefore landed on the login page after submitting — a confusing dead end.
- New behaviour: every Order gets a random `confirmation_token` (`SecureRandom.urlsafe_base64(24)`, indexed unique). After `create`, redirect goes to a new public route `GET /objednavka/:number?token=…` (`Storefront::OrderConfirmationsController#show`) that authorizes via `secure_compare(token, order.confirmation_token)` OR `Current.user.id == order.user_id`. Without either, 404.
- Migration: `add_confirmation_token_to_orders` on dev + prod. Backfilled 4 pre-existing orders with random tokens.
- Page (`app/views/storefront/order_confirmations/show.html.erb`): big green ✓ hero with order number + e-mail; 5-step status timeline (Přijata → Platba → Zpracování → Odesláno → Doručeno) that highlights the current step in rose and reached steps in emerald; "Co bude dál" 3-step explainer; full line-item summary + totals; doručovací adresa + payment-method block (with bank-transfer instructions including the variable symbol); "Pokračovat v nákupu" + "Vytvořit účet"/"Moje objednávky" footer.
- Mobile-first: timeline stacks vertically on phones and goes horizontal at `md:`; everything has 44 px tap targets; copy in Czech.
- Verified end-to-end: created an order in console, fetched `/objednavka/PK-202604-E63AA8?token=…` → 200 + 13 KB; without/with-wrong token → 404. Test order cleaned up after.

### 2026-04-25 — Cart UI: replace "OK" button with [−] [n] [+] stepper
- Old UX: cart-line had a number input + an underlined "OK" link to submit. Users had to change the number AND click OK separately.
- New UX (`app/views/storefront/cart/show.html.erb`): proper stepper. Minus button (disabled at 1) and plus button each fire a single `PATCH /kosik/polozka/:id` with the new quantity. The number field auto-submits on `change` and `blur` so typing "5" + tab still works without an explicit button. All controls are 44×44 px.
- Bonus mobile-first redesign of the same view: table collapses to stacked cards under `md:`, each card shows label-prefixed Množství/Cena, sticky subtotal bar, two-button footer ("Pokračovat v nákupu" + "Pokračovat k pokladně") that stacks on small screens.
- Required `bin/rails assets:precompile` to ship the new utility classes.

### 2026-04-25 — Cart add-to-cart off-by-one (qty=2 on first add)
- Bug: clicking "Vložit do košíku" once added quantity = 2, not 1. Each subsequent click also +2.
- Root cause: the cart_items migration used `t.integer :quantity, null: false, default: 1`, so `cart_items.find_or_initialize_by(product_id: …)` returns an in-memory object whose `quantity` is **already 1** (the DB default applied by Active Record). My old code did `item.quantity = item.quantity.to_i + quantity`, turning 1 + 1 = 2 on a fresh row.
- Fix (`app/models/cart.rb`): branch on persistence — `item.quantity = item.persisted? ? item.quantity.to_i + quantity : quantity`. Existing rows still increment; new rows are set to the requested quantity exactly.
- Regression test in console: 1st add (q=1) → 1; 2nd add (q=1) → 2; 3rd add (q=3) → 5; fresh product (q=1) → 1. All pass.
- Wiped CartItem + Cart in production after the fix landed; user's bad-state carts cleared.

### 2026-04-25 — Mobile blocker fix + search UX redesign
- **🚨 Production blocker found and removed**: `ApplicationController` had Rails 8's `allow_browser versions: :modern`, which was returning **HTTP 406 "Your browser is not supported"** to every iOS Safari user. Verified via `curl -A` with iPhone UA: blocked. Android Chrome and desktop worked. Removed the directive entirely (`app/controllers/application_controller.rb`); no current feature requires the bleeding-edge CSS `:has` / web-push surface that the `:modern` preset enforces. If a floor is ever needed, use a specific version map, not the `:modern` preset.
- **Header redesign for mobile** (`app/views/layouts/application.html.erb`): cart was previously `hidden md:flex` — invisible on phones. Now compact cart pill with shopping-cart SVG + counter is visible at every breakpoint, login becomes an icon-only button on mobile, search field auto-resizes (`flex-1 min-w-0`), header height ≤ ~64 px on mobile.
- **Search page mobile-first redesign** (`app/views/storefront/search/show.html.erb`): three distinct page states — empty (categories suggestion), no-results (friendly empty state), with-results (filter sidebar + grid). Filter sidebar is now a `<details>` element collapsed by default on mobile, always-open on `lg:`+. Tap targets bumped to `min-h-11` (44 px) on every facet row, sort dropdown, price inputs, submit buttons. Active-filter chips use whitespace-nowrap so they don't squish. Empty state CTAs sized to WCAG 2.5.5 minimums.
- **Sort form fix**: hidden inputs now correctly preserve all params except `sort` and `page`, so changing sort doesn't drop the query or filters.
- **Re-ran `bin/rails assets:precompile`** to regenerate Tailwind 4 CSS — new utility classes (`min-h-11`, `min-h-12`, `inputmode`, etc.) are now in the built stylesheet.

Verified post-deploy with `curl -A "Mozilla/5.0 (iPhone…)"` against `/`, `/hledat`, `/hledat?q=stabilo`, `/kategorie/*`, `/produkt/*`, `/kosik` — all 200, all serve real HTML.

### 2026-04-25 — Core rule 11: document every change in this file
- Added Rule 11 to **Critical project rules**: every production change must leave a Post-launch change log entry, with intent + root cause + file-path summary + side effects.
- Strengthens the older "How to log a new change" section by making it a *binding rule* rather than a suggestion.
- Reinforces existing rule that the change log is single source of truth for "what happened to Palkres" — git history and journalctl are secondary.

### 2026-04-25 — Core rule: mobile-first
- Added "Rule 10: Mobile-first is non-negotiable" to **Critical project rules**. Every view, partial, and component must start at the phone breakpoint and *enhance* upward via `sm:`/`md:`/`lg:`. Tap targets ≥ 44×44 px, single-column by default, no hover-only actions, body text ≥ 14 px, Lighthouse mobile ≥ 85 perf / 95 a11y.
- Pre-merge test recipe: DevTools at iPhone 14 (390 px) + Galaxy S23 (412 px), then 768 px + 1024 px.

### 2026-04-25 — Pretty pagination
- Replaced bare `pagy_nav` (default `<a>1</a><a>…</a>` strip) with a Tailwind-styled paginator across storefront + admin.
- New helper `ApplicationHelper#pagy_nav_pretty(pagy)` renders prev/next + numbered pages + gap dots as 40×40 px pill buttons; current page is solid rose, idle pages are white-with-hover, prev/next become disabled when at the edges.
- Updated views: `storefront/categories/show`, `storefront/search/show`, `admin/products/index`, `admin/orders/index`.

### 2026-04-25 — Search page redesign
- `Storefront::SearchController`: added filters (manufacturer via facet, in-stock toggle, price min/max) and six sort options (relevance/name/price/newest). Relevance ordering uses a `CASE WHEN unaccent(products.name) ILIKE 'query%' THEN 0 ELSE 1 END` prefix-match bias. Extended matcher to also hit `manufacturer_part_number`.
- `app/views/storefront/search/show.html.erb`: hero bar with inline search input + live result count; sticky left sidebar with price range inputs, in-stock checkbox, and top-20 manufacturer facet (counts shown); active filters displayed as removable chips; improved empty state with category suggestions CTA.
- SQL fix: qualified ambiguous `name` column as `products.name` after the manufacturers join.

### 2026-04-25 — Category button fix + Active Storage
- Bug: homepage red button "Prohlédnout katalog" and featured-category tiles all pointed at `#` because `Category#products_count` was 0 on every row. Cause: importer uses `ProductCategory.insert_all!` which bypasses the counter-cache trigger.
- Fix: importer now runs a single SQL `UPDATE categories SET products_count = …` over `product_categories JOIN products (active)` at the end of every sync, then invalidates the `storefront:root_categories:v1` fragment cache.
- Belt-and-braces: `Storefront::BaseController#load_category_tree` falls back to all roots if the counter-filtered scope is empty, so a bad cache can't hide the menu.
- Ran backfill once against prod DB (not a migration — it's in the importer now, so future syncs self-heal).
- Also ran `bin/rails active_storage:install` (prod + dev) — `ImageCacherJob` was silently crashing on missing `active_storage_blobs` table.

### 2026-04-25 — Cart add-to-cart UX
- Bug: clicking "Vložit do košíku" triggered a Turbo Stream POST that returned `head :no_content` (no template, no redirect) — the button did nothing visible, even though the item was added.
- Fix: `Storefront::CartController#add` now redirects to `/kosik` with `status: :see_other`, which Turbo follows correctly for all form submissions.

### 2026-04-25 — TLS / custom domain
- DNS: WEDOS A record `palkres.techtools.cz → 51.195.41.226`.
- Issued Let's Encrypt cert via `sudo certbot --nginx -d palkres.techtools.cz --redirect` (auto-renews via existing certbot timer).
- Verified HTTPS 200 for `/`, `/hledat`, `/kategorie/*`, `/produkt/*`, `/kosik`, `/session/new`; `/admin` 302s to login.

### 2026-04-24 — Initial build + deploy
- Full scaffolding, models, importer, storefront, admin, cart, checkout, and first successful ARTIKON import on dev and production databases. See commits (if/when repo is initialized) for granular diffs.

## Public routes

| Method | Path | Controller#action | Notes |
|---|---|---|---|
| GET  | `/`                                | `storefront/home#show`             | featured + topsellers + brands |
| GET  | `/hledat?q=…`                      | `storefront/search#show`           | filters: manufacturer / in-stock / price / sort |
| GET  | `/kategorie/*path`                 | `storefront/categories#show`       | nested category, subcategories, manufacturer facet |
| GET  | `/produkt/:slug`                   | `storefront/products#show`         | enqueues `ImageCacherJob` on first view |
| GET  | `/kosik`                           | `storefront/cart#show`             | guest + logged-in |
| POST | `/kosik/pridat/:product_id`        | `storefront/cart#add`              | redirects 303 → /kosik |
| POST | `/kosik/pridat-hromadne`           | `storefront/cart#bulk_add`         | bulk-add of variants from product page (`items[i][product_id]`, `items[i][quantity]`) |
| PATCH| `/kosik/polozka/:id`               | `storefront/cart#update`           | quantity stepper |
| DELETE| `/kosik/polozka/:id`              | `storefront/cart#remove`           | trash icon |
| GET  | `/pokladna`                        | `storefront/checkouts#show`        | 5-step form (Kontakt / Adresa / Doprava / Platba / Poznámka) |
| POST | `/pokladna`                        | `storefront/checkouts#create`      | persists Order + enqueues `OrderMailer.confirmation`, redirects to confirmation |
| GET  | `/objednavka/:number?token=…`      | `storefront/order_confirmations#show` | public, token- or owner-gated; 404 otherwise |
| GET  | `/uctu/orders` etc.                | `account/*`                        | requires authentication |
| GET  | `/admin*`                          | `admin/*`                          | requires `User#role == :admin` |
| GET/POST | `/session/new`, `/session`     | `sessions#*`                       | Czech card login |
| GET/POST/PUT | `/passwords/*`                | `passwords#*`                      | Czech reset flow |

## Verification checklist

- `bin/rails db:create db:migrate` green on all three envs
- `bin/rails artikon:sync` creates ~29 k products in < 10 min, memory < 300 MB; re-running yields 0 duplicates and increments `items_updated`
- Storefront 200 on `/`, `/hledat`, `/kategorie/*`, `/produkt/:slug`, `/kosik`, `/pokladna`, `/objednavka/:number?token=…`, `/session/new`, `/passwords/new`
- Mobile UA returns real HTML (not the Rails "browser unsupported" 406 stub) — see Rule 10
- iPhone + Android `curl -A` smoke pass on the routes above
- Cart: 1st add → qty 1, subsequent adds increment, [−] disables at 1, [+] caps at 99
- Checkout submit → 303 → `/objednavka/:number?token=…` 200 with timeline + QR for `bank_transfer`
- `OrderMailer.confirmation(id)` renders multipart HTML + text, inline `payment-qr.svg` attached, BCC to `info@palkres.cz`, subject `Potvrzení objednávky PK-… — Palkres`
- `Payments::CzechQr.placeholder?` returns false in prod env
- `/admin` 302→ login when anonymous; logged-in admin sees Přehled / Produkty / Objednávky / Syncy feedu
- `sudo systemctl status palkres-eshop.service` = active (running) with Puma + Solid Queue dispatcher / worker / scheduler
- Solid Queue cron loaded: `clear_solid_queue_finished_jobs` + `artikon_nightly_sync`
- TLS valid (Let's Encrypt via certbot timer auto-renews)

## How to log a new change

Every production-visible change appends a dated section to **Post-launch change log** above the previous entry. Format:

```
### YYYY-MM-DD — short title
- What broke or what changed (user-visible).
- Root cause.
- Fix: file paths + what you did.
- Side effects / follow-ups.
```

The change log is the single source of truth for "what happened" — git history is secondary.

## Out of scope (current build)

- Multi-language storefront (CZ only)
- Multiple suppliers (ARTIKON only)
- B2B dealer pricing UI
- Loyalty / gift cards / coupons
- Pohoda / Money S3 / Fakturoid invoicing integration
