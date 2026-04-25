require "nokogiri"

module Artikon
  # Nokogiri SAX handler that streams <SHOPITEM> blocks out of the ARTIKON feed.
  # Instantiate with a block; the block is invoked once per completed SHOPITEM with
  # a Hash representation. CDATA values are unwrapped to plain strings.
  #
  # Usage:
  #   handler = FeedSaxHandler.new { |item| puts item["PRODUCTID"] }
  #   Nokogiri::XML::SAX::Parser.new(handler).parse(io)
  class FeedSaxHandler < Nokogiri::XML::SAX::Document
    ROOT_ITEM = "SHOPITEM".freeze
    CATEGORIES_CONTAINER = "CATEGORIES".freeze
    CAT_ELEMENT = "CAT".freeze
    PARAM_ELEMENT = "PARAM".freeze

    def initialize(&on_item)
      @on_item = on_item
      reset_item!
      @buffer = +""
      @in_item = false
      @in_categories = false
      @current_param = nil
      @item_count = 0
    end

    attr_reader :item_count

    def start_element(name, _attrs = [])
      case name
      when ROOT_ITEM
        reset_item!
        @in_item = true
      when CATEGORIES_CONTAINER
        @in_categories = true
      when PARAM_ELEMENT
        @current_param = {}
      end
      @buffer = +""
    end

    def end_element(name)
      return unless @in_item

      case name
      when ROOT_ITEM
        @on_item.call(@item) if @on_item
        @item_count += 1
        @in_item = false
      when CATEGORIES_CONTAINER
        @in_categories = false
      when CAT_ELEMENT
        @item["_categories"] << @buffer.strip if @in_categories
      when PARAM_ELEMENT
        if @current_param && @current_param[:name]
          @item["_params"] << @current_param
        end
        @current_param = nil
      else
        if @current_param
          key = name.downcase.to_sym
          @current_param[key] = @buffer.strip if %i[name val].include?(key)
        else
          # Only set if key not already present (avoids overwriting when a child tag
          # closes inside this one) — but ARTIKON feed is flat, so simple assignment is fine.
          @item[name] = @buffer.strip
        end
      end
      @buffer = +""
    end

    def characters(string)
      @buffer << string if @in_item
    end

    def cdata_block(string)
      @buffer << string if @in_item
    end

    def error(msg)
      Rails.logger.warn("[ArtikonSAX] #{msg}")
    end

    private

    def reset_item!
      @item = { "_categories" => [], "_params" => [] }
    end
  end
end
