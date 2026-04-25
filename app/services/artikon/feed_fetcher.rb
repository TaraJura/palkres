require "net/http"
require "uri"
require "fileutils"

module Artikon
  class FeedFetcher
    DEFAULT_URL = ENV.fetch("ARTIKON_FEED_URL",
      "https://www.artikon.cz/feeds/xml/VO_XML_Feed_Komplet_2.xml").freeze

    CACHE_DIR = Rails.root.join("tmp", "artikon").freeze

    Result = Struct.new(:path, :etag, :last_modified, :not_modified, keyword_init: true)

    def initialize(url: DEFAULT_URL, previous_etag: nil, previous_last_modified: nil)
      @url = url
      @previous_etag = previous_etag
      @previous_last_modified = previous_last_modified
    end

    # Streams the feed to disk (tmp/artikon/feed.xml) and returns the local path.
    # Returns Result with not_modified=true if server replied 304.
    def call
      FileUtils.mkdir_p(CACHE_DIR)
      uri = URI(@url)
      request = Net::HTTP::Get.new(uri)
      request["If-None-Match"]     = @previous_etag          if @previous_etag.present?
      request["If-Modified-Since"] = @previous_last_modified if @previous_last_modified.present?
      request["User-Agent"]        = "palkres-eshop-importer/1.0"

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 300) do |http|
        http.request(request) do |response|
          case response
          when Net::HTTPNotModified
            return Result.new(path: nil, etag: @previous_etag, last_modified: @previous_last_modified, not_modified: true)
          when Net::HTTPSuccess
            path = CACHE_DIR.join("feed.xml")
            File.open(path, "wb") do |f|
              response.read_body { |chunk| f.write(chunk) }
            end
            return Result.new(
              path: path.to_s,
              etag: response["ETag"],
              last_modified: response["Last-Modified"],
              not_modified: false
            )
          else
            raise "ARTIKON feed HTTP #{response.code}: #{response.message}"
          end
        end
      end
    end
  end
end
