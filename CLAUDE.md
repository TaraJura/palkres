# CLAUDE.md — Palkres e-shop

Rails 8.1.2 + PostgreSQL e-shop for **Palkres s.r.o.** (art & stationery supplies).
Primary supplier: **ARTIKON s.r.o.** via XML feed.

## Ownership & team

- **Architect / developer / maintainer**: Jiří Novák (Techtools), <jiri.novak@techtools.cz>, +420 603 328 374
- **Client**: Palkres s.r.o. — Pavel Holuša, <palkres@seznam.cz>
- **Project status (2026-04-25)**: free functional-prototype phase, live at https://palkres.techtools.cz
- **Commercial terms**: first demo **free**, per the 2026-04-22 pitch (AI-first workflow, 3–5× faster delivery). Final cenová kalkulace + harmonogram due after in-person meeting.

Claude Code (Opus 4.7) is the AI pair-programmer that scaffolded, built, and deploys the stack end-to-end under Jiří's direction. Any future automated agent (scheduled or ad-hoc) should read **this file first**, then the memory index at `~/.claude/projects/-home-novakj/memory/MEMORY.md` (which links to `project_palkres.md`) before making changes.

## At-a-glance

- **Location**: `/home/novakj/palkres-eshop`
- **Ruby / Rails**: 4.0.1 / 8.1.2
- **Database**: PostgreSQL 17 (role `palkres`, DBs `palkres_eshop_{dev,test,prod}`)
- **Port (prod)**: 3003 (systemd service `palkres-eshop.service`)
- **Supplier feed**: `https://www.artikon.cz/feeds/xml/VO_XML_Feed_Komplet_2.xml` (~163 MB, ~29,222 products)

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
- `/kategorie/*path` — category listing w/ left-tree sidebar, pagy pagination, facets
- `/produkt/:slug` — detail page, gallery, add to cart
- `/hledat?q=…` — FTS + trigram fuzzy
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

### 11. Document EVERY change in this CLAUDE.md — no exceptions
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

7. **If you skip this**, the next Claude session (or Jiří six months from now) will rediscover the same bug, redo the same backfill, or fight the same convention. That cost is on you.

The change log is the **single source of truth for "what happened to Palkres"**. Git is secondary, journalctl is tertiary.

## Data model

| Model | Key fields |
|---|---|
| `User` | email, password_digest, role enum (customer/dealer/admin), first/last_name, phone |
| `Address` | user_id, kind (billing/shipping), street, city, postal_code, country, company, ico, dic |
| `Category` | ancestry, slug (friendly_id), name, external_path |
| `Manufacturer` | slug, name |
| `Product` | artikon_id (uniq), sku, ean, slug, name, description (html), description_short, manufacturer_id, weight_kg, tax_rate, state, price_retail_cents, price_dealer_cents, price_wo_tax_cents, currency, stock_amount, availability_label, availability_days, item_group_id, supplier_url, active, synced_at |
| `ProductCategory` | product_id, category_id |
| `ProductImage` | product_id, url, position, has_attached_blob? |
| `Cart` | user_id (nullable), session_token |
| `CartItem` | cart_id, product_id, quantity, unit_price_cents |
| `Order` | number, user_id, status, subtotal_cents, shipping_cents, tax_cents, total_cents, payment_state, shipping_state, billing/shipping_address jsonb, notes |
| `OrderItem` | order_id, product_id, name_snapshot, sku_snapshot, quantity, unit_price_cents |
| `Payment` | order_id, gateway, gateway_ref, amount_cents, status, raw_response jsonb |
| `Shipment` | order_id, carrier, tracking_number, label_url, status |
| `SyncRun` | started_at, finished_at, feed_etag, feed_last_modified, items_seen, items_created, items_updated, items_deactivated, errors jsonb |

## Key paths

| Resource | Path |
|---|---|
| App root | `/home/novakj/palkres-eshop/` |
| ARTIKON importer | `app/services/artikon/` |
| Nightly sync job | `app/jobs/artikon_sync_job.rb` |
| Image cacher | `app/jobs/image_cacher_job.rb` |
| Recurring config | `config/recurring.yml` |
| DB config | `config/database.yml` (reads `.env`) |
| Systemd unit | `/etc/systemd/system/palkres-eshop.service` |
| Nginx site | `/etc/nginx/sites-available/palkres.techtools.cz` |
| Env file (dev) | `.env` (gitignored) |

## Common commands

```bash
# Dev server
bin/dev

# Console
RAILS_ENV=development bin/rails console

# Manual ARTIKON sync
bin/rails artikon:sync

# Background jobs (Solid Queue) in production
bin/jobs

# Migrations (always backup prod first)
bin/rails db:migrate

# Logs (production)
sudo journalctl -u palkres-eshop.service -f
```

## Build order (all phase-1 tasks complete as of 2026-04-25)

1. ✅ Scaffold — `rails new -d postgresql --css=tailwind`
2. ✅ Postgres role/DBs — `palkres` role + three DBs (dev/test/prod)
3. ✅ This CLAUDE.md
4. ✅ Auth — `bin/rails g authentication`, role enum (customer/dealer/admin), admin seed
5. ✅ Catalog models — Category/Manufacturer/Product/ProductCategory/ProductImage/SyncRun + Cart/Order/Payment/Shipment
6. ✅ ARTIKON importer — fetcher, SAX handler, tree builder, orchestrator, `artikon:sync` rake task
7. ✅ First real import — **29 222 products / 668 categories / 105 manufacturers / 136 283 links / 29 206 images** in ~85 s, peak RSS 227 MB
8. ✅ Storefront MVP — home, category, product, search, pagy, Tailwind
9. ✅ Cart + checkout — Turbo-driven, guest flow, stubbed shipping/payment
10. ✅ Admin + schedule — `/admin/*` + `config/recurring.yml` → `ArtikonSyncJob` at 03:00
11. ✅ Production deploy — systemd `palkres-eshop.service`, nginx `palkres.techtools.cz`, Let's Encrypt TLS (expires 2026-07-23)

## Post-launch change log

Newest at top. Every non-trivial production change should append an entry here.

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
- Added Rule 11 to **Critical project rules**: every production change must leave a Post-launch change log entry, with intent + root cause + file-path summary + side effects. Architect/main-developer role (Claude Code under Jiří's direction) is named explicitly so the responsibility is unambiguous.
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
- DNS: WEDOS A record `palkres.techtools.cz → 51.195.41.226` created by Jiří.
- Issued Let's Encrypt cert via `sudo certbot --nginx -d palkres.techtools.cz --redirect` (auto-renews via existing certbot timer).
- Verified HTTPS 200 for `/`, `/hledat`, `/kategorie/*`, `/produkt/*`, `/kosik`, `/session/new`; `/admin` 302s to login.

### 2026-04-24 — Initial build + deploy
- Full scaffolding, models, importer, storefront, admin, cart, checkout, and first successful ARTIKON import on dev and production databases. See commits (if/when repo is initialized) for granular diffs.

## Verification checklist

- `bin/rails db:create db:migrate` green
- `bin/rails artikon:sync` creates ~29k products in < 10 min, memory < 300 MB
- Homepage responds 200, category + product pages render
- Cart → checkout → order with GoPay sandbox → admin sees pending → webhook → paid
- `sudo systemctl status palkres-eshop.service` = active (running)
- Nightly `ArtikonSyncJob` scheduled via Solid Queue `recurring.yml`
- Re-running sync yields 0 duplicates and correct updated counts

## How to log a new change

Every time you (Claude or human) make a visible production change, append a new dated section to **Post-launch change log** above the previous entry. Format:

```
### YYYY-MM-DD — short title
- What broke or what changed (user-visible).
- Root cause.
- Fix: file paths + what you did.
- Side effects / follow-ups.
```

This file is the single source of truth for "what happened to Palkres". Git history is secondary — the change log is human-readable and survives rebases.

## Out of scope for first client demo

- Multi-language storefront (CZ only; stubbed for sk/en later)
- Multiple suppliers (ARTIKON only)
- B2B dealer pricing UI
- Loyalty / gift cards / coupons
- Pohoda / Money S3 / Fakturoid invoicing integration

## Open questions for Pavel Holuša (next meeting)

- Domain? (`palkres.cz`, `palkres-vytvarne.cz`, other?)
- Payment gateway — GoPay / ComGate / Stripe / bank transfer?
- Shipping carriers — Zásilkovna / Česká pošta / DPD / PPL / osobní odběr?
- VAT ID invoicing requirements from day 1?
- Brand: logo, color palette, hero imagery
- Any other suppliers planned? (Drives supplier-abstraction timing.)
