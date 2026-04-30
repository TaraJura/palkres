require "nokogiri"

module Artikon
  # Orchestrates the full ARTIKON feed import:
  #   1. Fetch (with If-None-Match / If-Modified-Since)
  #   2. Single SAX pass that upserts Product + attaches Categories/Manufacturers/Images
  #   3. Deactivates products no longer present in the feed
  #   4. Records a SyncRun with counts + errors
  #
  # Memory-safe: SAX streaming, upsert batches of 500, categories/manufacturers cached
  # in a Hash so we never do N+1 per product.
  class FeedImporter
    BATCH_SIZE = 500

    def initialize(url: Artikon::FeedFetcher::DEFAULT_URL, logger: Rails.logger)
      @url = url
      @logger = logger
    end

    def call
      previous = SyncRun.where(source: "artikon", status: "succeeded").order(:started_at).last
      sync = SyncRun.create!(source: "artikon", started_at: Time.current, status: "running")

      begin
        fetch_result = FeedFetcher.new(
          url: @url,
          previous_etag: previous&.feed_etag,
          previous_last_modified: previous&.feed_last_modified
        ).call

        if fetch_result.not_modified
          sync.update!(status: "skipped", finished_at: Time.current,
                       feed_etag: fetch_result.etag, feed_last_modified: fetch_result.last_modified)
          @logger.info("[ArtikonImport] feed not modified, skipping")
          return sync
        end

        sync.update!(feed_etag: fetch_result.etag, feed_last_modified: fetch_result.last_modified)

        seen_artikon_ids = Set.new
        product_buffer = []
        category_cache = {}          # external_path => Category (loaded lazily)
        manufacturer_cache = {}      # name (downcased) => Manufacturer
        pending_associations = []    # [{ artikon_id:, category_paths:, manufacturer_name:, image_url:, image_url_big: }, …]
        categories_created = 0
        manufacturers_created = 0

        handler = FeedSaxHandler.new do |raw|
          attrs = map_item(raw)
          next unless attrs[:artikon_id].present?

          seen_artikon_ids << attrs[:artikon_id]
          product_buffer << attrs
          pending_associations << {
            artikon_id: attrs[:artikon_id],
            category_paths: raw["_categories"].to_a.uniq,
            manufacturer_name: raw["MANUFACTURER"].to_s.strip,
            image_url: raw["IMAGE"].to_s.strip,
            image_url_big: raw["IMAGE_BIG"].to_s.strip
          }

          if product_buffer.size >= BATCH_SIZE
            flush_products!(product_buffer, pending_associations,
                            category_cache, manufacturer_cache,
                            categories_created_ref: ->(n) { categories_created += n },
                            manufacturers_created_ref: ->(n) { manufacturers_created += n })
            product_buffer.clear
            pending_associations.clear
          end
        end

        File.open(fetch_result.path, "rb") do |io|
          Nokogiri::XML::SAX::Parser.new(handler).parse(io)
        end

        if product_buffer.any?
          flush_products!(product_buffer, pending_associations,
                          category_cache, manufacturer_cache,
                          categories_created_ref: ->(n) { categories_created += n },
                          manufacturers_created_ref: ->(n) { manufacturers_created += n })
          product_buffer.clear
          pending_associations.clear
        end

        # Soft-deactivate products missing from feed
        deactivated = Product.active.where.not(artikon_id: seen_artikon_ids.to_a).update_all(active: false, updated_at: Time.current)

        # Backfill category product counts (bulk insert_all bypassed the counter cache)
        ActiveRecord::Base.connection.execute(<<~SQL.squish)
          UPDATE categories SET products_count = sub.cnt FROM (
            SELECT c.id, COUNT(pc.id) AS cnt
            FROM categories c
            LEFT JOIN product_categories pc ON pc.category_id = c.id
            LEFT JOIN products p ON p.id = pc.product_id AND p.active
            GROUP BY c.id
          ) sub WHERE categories.id = sub.id
        SQL
        Rails.cache.delete("storefront:root_categories:v1")

        sync.update!(
          status: "succeeded",
          finished_at: Time.current,
          items_seen: handler.item_count,
          items_deactivated: deactivated,
          categories_created: categories_created,
          manufacturers_created: manufacturers_created,
          items_created: @created_count.to_i,
          items_updated: @updated_count.to_i
        )
        @logger.info("[ArtikonImport] done: seen=#{handler.item_count} created=#{@created_count} updated=#{@updated_count} deactivated=#{deactivated}")
        sync
      rescue => e
        sync.record_error!(e.message, backtrace: e.backtrace&.first(8))
        sync.update!(status: "failed", finished_at: Time.current)
        raise
      end
    end

    private

    # Build Product attribute hash from raw SAX item.
    # MUST return the same set of keys for every item so that upsert_all works.
    def map_item(raw)
      price_w  = raw["PRICE_W_TAX"].to_s.gsub(",", ".").to_f
      price_wo = raw["PRICE_WO_TAX"].to_s.gsub(",", ".").to_f
      dealer   = raw["PRICE_W_cr_dealer"].to_s.gsub(",", ".").to_f
      item_group_id = raw["ITEMGROUP_ID"].presence
      group_image_url =
        if item_group_id&.match?(/\A\d+\z/)
          "https://www.artikon.cz/deploy/img/products/#{item_group_id}/#{item_group_id}.jpg"
        end

      {
        artikon_id: raw["PRODUCTID"].to_s.strip,
        sku: raw["PRODUCTNUMBER"].presence,
        ean: raw["EAN"].presence,
        name: raw["NAME"].to_s.strip,
        slug: friendly_slug(raw["NAME"], raw["PRODUCTID"]),
        description_html: raw["DESC"],
        description_short: raw["DESC_SHORT"].presence || raw["DESC_CLEAN"],
        description_clean: raw["DESC_CLEAN"],
        manufacturer_id: nil, # filled in during flush_products!
        weight_kg: raw["WEIGHT"].to_s.gsub(",", ".").to_f,
        tax_rate: raw["TAX"].to_i.nonzero? || 21,
        state: raw["STATE"].presence || "new",
        currency: "CZK",
        price_retail_cents:   (price_w  * 100).round,
        price_dealer_cents:   (dealer   * 100).round,
        price_wo_tax_cents:   (price_wo * 100).round,
        stock_amount: raw["AMOUNT"].to_i,
        availability_label: raw["AVAILABILITY"].presence,
        availability_days: raw["AVAILABILITY_DAYS"].to_i,
        item_group_id: item_group_id,
        group_image_url: group_image_url,
        supplier_url: raw["LINK"].presence,
        manufacturer_part_number: raw["PN_MANUFACTURER"].presence,
        topseller: raw["MERGADO_TOPSELLER"].to_s == "1",
        active: true,
        synced_at: Time.current
      }
    end

    def friendly_slug(name, artikon_id)
      base = name.to_s.parameterize.presence || "produkt"
      "#{base}-#{artikon_id.to_s.parameterize}"[0, 200]
    end

    def flush_products!(attrs_batch, associations, category_cache, manufacturer_cache,
                        categories_created_ref:, manufacturers_created_ref:)
      @created_count ||= 0
      @updated_count ||= 0

      # 1. Resolve manufacturers (one trip per new name)
      associations.each do |assoc|
        name = assoc[:manufacturer_name]
        next if name.blank?
        key = name.downcase
        unless manufacturer_cache.key?(key)
          m = Manufacturer.find_or_create_by!(name: name)
          manufacturer_cache[key] = m
          manufacturers_created_ref.call(1) if m.previously_new_record?
        end
      end

      # 2. Attach manufacturer_id to each product attrs
      attrs_batch.each_with_index do |attrs, i|
        mname = associations[i][:manufacturer_name]
        attrs[:manufacturer_id] = manufacturer_cache[mname.downcase]&.id if mname.present?
      end

      # 3. Upsert products (de-dupe by artikon_id within the batch in case the feed repeats)
      dedup_batch = attrs_batch.uniq { |a| a[:artikon_id] }
      before_ids = Product.where(artikon_id: dedup_batch.map { |a| a[:artikon_id] }).pluck(:artikon_id).to_set
      Product.upsert_all(dedup_batch,
                         unique_by: :artikon_id,
                         update_only: dedup_batch.first.keys - [:slug, :artikon_id])
      dedup_batch.each do |a|
        if before_ids.include?(a[:artikon_id])
          @updated_count += 1
        else
          @created_count += 1
        end
      end

      # 4. Load product id map for this batch
      pid_map = Product.where(artikon_id: attrs_batch.map { |a| a[:artikon_id] }).pluck(:artikon_id, :id).to_h

      # 5. Resolve categories (create missing on demand)
      associations.each do |assoc|
        assoc[:category_paths].each do |path|
          next if path.blank?
          next if category_cache.key?(path)
          cat = Category.find_or_create_from_path(path)
          if cat
            category_cache[path] = cat
            # roughly track creation: count parts not previously in cache
            # (we can't easily know how many new rows were created by ancestry walk)
          end
        end
      end
      # Update counter (approximate - based on total Category rows delta is handled externally).

      # 6. Sync product_categories (replace-on-write for the batch)
      product_ids = pid_map.values
      ProductCategory.where(product_id: product_ids).delete_all
      pc_rows = []
      associations.each do |assoc|
        pid = pid_map[assoc[:artikon_id]]
        next unless pid
        assoc[:category_paths].each_with_index do |path, idx|
          cat = category_cache[path]
          next unless cat
          pc_rows << { product_id: pid, category_id: cat.id, primary: idx.zero?, created_at: Time.current, updated_at: Time.current }
        end
      end
      ProductCategory.insert_all!(pc_rows) if pc_rows.any?

      # 7. Sync product_images (simple replace: one row for the big image, optionally one for thumbnail)
      ProductImage.where(product_id: product_ids).delete_all
      img_rows = []
      associations.each do |assoc|
        pid = pid_map[assoc[:artikon_id]]
        next unless pid
        if assoc[:image_url_big].present?
          img_rows << { product_id: pid, url: assoc[:image_url_big], url_big: assoc[:image_url_big],
                        position: 0, cached: false, created_at: Time.current, updated_at: Time.current }
        elsif assoc[:image_url].present?
          img_rows << { product_id: pid, url: assoc[:image_url], url_big: assoc[:image_url],
                        position: 0, cached: false, created_at: Time.current, updated_at: Time.current }
        end
      end
      ProductImage.insert_all!(img_rows) if img_rows.any?
    end
  end
end
