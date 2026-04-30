# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_04_30_135044) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"
  enable_extension "unaccent"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "addresses", force: :cascade do |t|
    t.string "city", null: false
    t.string "company"
    t.string "country_code", default: "CZ", null: false
    t.datetime "created_at", null: false
    t.string "dic"
    t.string "first_name"
    t.string "ico"
    t.integer "kind", default: 0, null: false
    t.string "last_name"
    t.string "phone"
    t.string "postal_code", null: false
    t.string "street", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_addresses_on_user_id"
  end

  create_table "cart_items", force: :cascade do |t|
    t.bigint "cart_id", null: false
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.integer "quantity", default: 1, null: false
    t.integer "unit_price_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["cart_id", "product_id"], name: "index_cart_items_on_cart_id_and_product_id", unique: true
    t.index ["cart_id"], name: "index_cart_items_on_cart_id"
    t.index ["product_id"], name: "index_cart_items_on_product_id"
  end

  create_table "carts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "session_token", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["session_token"], name: "index_carts_on_session_token", unique: true
    t.index ["user_id"], name: "index_carts_on_user_id"
  end

  create_table "categories", force: :cascade do |t|
    t.string "ancestry"
    t.integer "ancestry_depth", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "external_path"
    t.string "name", null: false
    t.integer "products_count", default: 0, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["ancestry"], name: "index_categories_on_ancestry"
    t.index ["external_path"], name: "index_categories_on_external_path", unique: true
    t.index ["slug"], name: "index_categories_on_slug", unique: true
  end

  create_table "manufacturers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_manufacturers_on_name", unique: true
    t.index ["slug"], name: "index_manufacturers_on_slug", unique: true
  end

  create_table "order_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "line_total_cents", null: false
    t.string "name_snapshot", null: false
    t.bigint "order_id", null: false
    t.bigint "product_id"
    t.integer "quantity", null: false
    t.string "sku_snapshot"
    t.integer "unit_price_cents", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["product_id"], name: "index_order_items_on_product_id"
  end

  create_table "orders", force: :cascade do |t|
    t.jsonb "billing_address", default: {}, null: false
    t.string "confirmation_token"
    t.datetime "created_at", null: false
    t.string "currency", default: "CZK", null: false
    t.string "email", null: false
    t.text "notes"
    t.string "number", null: false
    t.string "payment_method"
    t.integer "payment_state", default: 0, null: false
    t.string "phone"
    t.datetime "placed_at"
    t.jsonb "shipping_address", default: {}, null: false
    t.integer "shipping_cents", default: 0, null: false
    t.string "shipping_method"
    t.integer "shipping_state", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.integer "subtotal_cents", default: 0, null: false
    t.integer "tax_cents", default: 0, null: false
    t.integer "total_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["confirmation_token"], name: "index_orders_on_confirmation_token", unique: true
    t.index ["number"], name: "index_orders_on_number", unique: true
    t.index ["status", "created_at"], name: "index_orders_on_status_and_created_at"
    t.index ["user_id"], name: "index_orders_on_user_id"
  end

  create_table "payments", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "CZK", null: false
    t.string "gateway", null: false
    t.string "gateway_ref"
    t.bigint "order_id", null: false
    t.jsonb "raw_response", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["gateway_ref"], name: "index_payments_on_gateway_ref"
    t.index ["order_id"], name: "index_payments_on_order_id"
  end

  create_table "product_categories", force: :cascade do |t|
    t.bigint "category_id", null: false
    t.datetime "created_at", null: false
    t.boolean "primary", default: false, null: false
    t.bigint "product_id", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_product_categories_on_category_id"
    t.index ["product_id", "category_id"], name: "index_product_categories_on_product_id_and_category_id", unique: true
    t.index ["product_id"], name: "index_product_categories_on_product_id"
  end

  create_table "product_images", force: :cascade do |t|
    t.boolean "cached", default: false, null: false
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.bigint "product_id", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.string "url_big"
    t.index ["product_id", "position"], name: "index_product_images_on_product_id_and_position"
    t.index ["product_id"], name: "index_product_images_on_product_id"
    t.index ["url"], name: "index_product_images_on_url"
  end

  create_table "products", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "artikon_id", null: false
    t.integer "availability_days"
    t.string "availability_label"
    t.datetime "created_at", null: false
    t.string "currency", default: "CZK", null: false
    t.text "description_clean"
    t.text "description_html"
    t.text "description_short"
    t.string "ean"
    t.string "group_image_url"
    t.string "item_group_id"
    t.bigint "manufacturer_id"
    t.string "manufacturer_part_number"
    t.string "name", null: false
    t.integer "price_dealer_cents", default: 0, null: false
    t.integer "price_retail_cents", default: 0, null: false
    t.integer "price_wo_tax_cents", default: 0, null: false
    t.string "sku"
    t.string "slug", null: false
    t.string "state", default: "new"
    t.integer "stock_amount", default: 0, null: false
    t.string "supplier_url"
    t.datetime "synced_at"
    t.integer "tax_rate", default: 21
    t.boolean "topseller", default: false, null: false
    t.datetime "updated_at", null: false
    t.decimal "weight_kg", precision: 10, scale: 3, default: "0.0"
    t.index ["active"], name: "index_products_on_active"
    t.index ["artikon_id"], name: "index_products_on_artikon_id", unique: true
    t.index ["ean"], name: "index_products_on_ean"
    t.index ["manufacturer_id", "active"], name: "index_products_on_manufacturer_id_and_active"
    t.index ["manufacturer_id"], name: "index_products_on_manufacturer_id"
    t.index ["name"], name: "index_products_on_name", opclass: :gin_trgm_ops, using: :gin
    t.index ["sku"], name: "index_products_on_sku"
    t.index ["slug"], name: "index_products_on_slug", unique: true
    t.index ["topseller"], name: "index_products_on_topseller"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "shipments", force: :cascade do |t|
    t.string "carrier", null: false
    t.datetime "created_at", null: false
    t.string "label_url"
    t.bigint "order_id", null: false
    t.jsonb "raw_response", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.string "tracking_number"
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_shipments_on_order_id"
    t.index ["tracking_number"], name: "index_shipments_on_tracking_number"
  end

  create_table "sync_runs", force: :cascade do |t|
    t.integer "categories_created", default: 0, null: false
    t.datetime "created_at", null: false
    t.jsonb "errors_log", default: [], null: false
    t.string "feed_etag"
    t.string "feed_last_modified"
    t.datetime "finished_at"
    t.integer "items_created", default: 0, null: false
    t.integer "items_deactivated", default: 0, null: false
    t.integer "items_seen", default: 0, null: false
    t.integer "items_updated", default: 0, null: false
    t.integer "manufacturers_created", default: 0, null: false
    t.string "source", default: "artikon", null: false
    t.datetime "started_at", null: false
    t.string "status", default: "running", null: false
    t.datetime "updated_at", null: false
    t.index ["source", "status"], name: "index_sync_runs_on_source_and_status"
    t.index ["started_at"], name: "index_sync_runs_on_started_at"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "first_name"
    t.string "last_name"
    t.string "password_digest", null: false
    t.string "phone"
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["role"], name: "index_users_on_role"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "addresses", "users"
  add_foreign_key "cart_items", "carts"
  add_foreign_key "cart_items", "products"
  add_foreign_key "carts", "users"
  add_foreign_key "order_items", "orders"
  add_foreign_key "order_items", "products"
  add_foreign_key "orders", "users"
  add_foreign_key "payments", "orders"
  add_foreign_key "product_categories", "categories"
  add_foreign_key "product_categories", "products"
  add_foreign_key "product_images", "products"
  add_foreign_key "products", "manufacturers"
  add_foreign_key "sessions", "users"
  add_foreign_key "shipments", "orders"
end
