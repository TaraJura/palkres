# Palkres e-shop

Rails 8 e-shop for **Palkres s.r.o.** — výtvarné potřeby a papírnictví — with
ARTIKON s.r.o. as the primary supplier.

- **Live**: https://palkres.techtools.cz
- **Architect / maintainer**: Jiří Novák (Techtools) — jiri.novak@techtools.cz
- **Client**: Pavel Holuša — palkres@seznam.cz

## Stack

- Ruby 4.0.1, Rails 8.1.2, PostgreSQL 17
- Tailwind CSS 4, Hotwire (Turbo + Stimulus), import-maps
- Solid Queue (nightly ARTIKON sync), Solid Cache, Solid Cable
- Ancestry (category tree), FriendlyId (slugs), Pagy, Money-Rails
- ARTIKON feed consumed via Nokogiri SAX streaming (~163 MB / ~29 k items in < 90 s)

## Quick start (development)

```bash
# 1. Install deps
bundle install

# 2. Create .env (git-ignored) with:
#    PALKRES_DB_USER=palkres
#    PALKRES_DB_PASSWORD=...
#    PALKRES_DB_HOST=127.0.0.1
#    ARTIKON_FEED_URL=https://www.artikon.cz/feeds/xml/VO_XML_Feed_Komplet_2.xml
#    RAILS_MASTER_KEY=<contents of config/master.key>

# 3. Create + migrate DBs
bin/rails db:create db:migrate db:seed

# 4. First import (~90 s, ~230 MB peak RSS)
bin/rails artikon:sync

# 5. Dev server
bin/dev
# → http://localhost:3000
```

Admin: `admin@palkres.cz` / `palkres-admin-2026` (seeded in `db/seeds.rb`).

## Deployment

- **Port**: 3003, via systemd unit `palkres-eshop.service`
- **Reverse proxy**: nginx at `/etc/nginx/sites-available/palkres.techtools.cz`
- **TLS**: Let's Encrypt via certbot (auto-renew)
- **Nightly sync**: Solid Queue `config/recurring.yml` → `ArtikonSyncJob` at 03:00 Europe/Prague

See `CLAUDE.md` for architecture deep-dive, data model, change log, and operational rules.

## Layout

```
app/services/artikon/    ARTIKON XML feed fetcher + SAX streaming importer
app/jobs/                ArtikonSyncJob (nightly), ImageCacherJob (on-demand)
app/controllers/storefront/   Public e-shop (home, category, product, search, cart, checkout)
app/controllers/account/      Logged-in customer area
app/controllers/admin/        Back-office (products, orders, sync runs)
config/recurring.yml     Solid Queue cron
```

## License

Proprietary — © 2026 Palkres s.r.o. / Techtools.
