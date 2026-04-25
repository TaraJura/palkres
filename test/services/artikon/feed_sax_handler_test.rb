require "minitest/autorun"
require_relative "../../../config/environment" unless defined?(Rails)
require "nokogiri"
require Rails.root.join("app/services/artikon/feed_sax_handler").to_s

class Artikon::FeedSaxHandlerTest < Minitest::Test
  FIXTURE = <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <SHOP>
      <SHOPITEM>
        <PRODUCTID><![CDATA[Sun-1]]></PRODUCTID>
        <NAME><![CDATA[Produkt 1]]></NAME>
        <PRICE_W_TAX>119</PRICE_W_TAX>
        <PRICE_WO_TAX>98</PRICE_WO_TAX>
        <MANUFACTURER><![CDATA[Stabilo]]></MANUFACTURER>
        <CATEGORIES>
          <CAT><![CDATA[PAPÍRNICTVÍ / Kancelářské potřeby]]></CAT>
          <CAT><![CDATA[KRESBA / Pomůcky]]></CAT>
        </CATEGORIES>
      </SHOPITEM>
      <SHOPITEM>
        <PRODUCTID><![CDATA[Sun-2]]></PRODUCTID>
        <NAME><![CDATA[Produkt 2]]></NAME>
        <PRICE_W_TAX>29</PRICE_W_TAX>
        <PRICE_WO_TAX>24</PRICE_WO_TAX>
        <MANUFACTURER><![CDATA[Koh-i-noor]]></MANUFACTURER>
        <CATEGORIES>
          <CAT><![CDATA[PAPÍRNICTVÍ]]></CAT>
        </CATEGORIES>
      </SHOPITEM>
      <SHOPITEM>
        <PRODUCTID><![CDATA[Sun-3]]></PRODUCTID>
        <NAME><![CDATA[Produkt 3]]></NAME>
        <PRICE_W_TAX>50</PRICE_W_TAX>
        <PRICE_WO_TAX>41</PRICE_WO_TAX>
      </SHOPITEM>
    </SHOP>
  XML

  def test_yields_one_hash_per_shopitem
    items = []
    handler = Artikon::FeedSaxHandler.new { |item| items << item }
    Nokogiri::XML::SAX::Parser.new(handler).parse(FIXTURE)

    assert_equal 3, handler.item_count
    assert_equal 3, items.size
    first = items.first
    assert_equal "Sun-1",                    first["PRODUCTID"]
    assert_equal "Produkt 1",                first["NAME"]
    assert_equal "119",                      first["PRICE_W_TAX"]
    assert_equal "Stabilo",                  first["MANUFACTURER"]
    assert_equal ["PAPÍRNICTVÍ / Kancelářské potřeby", "KRESBA / Pomůcky"],
                 first["_categories"]
    assert_equal [], items.last["_categories"]
  end
end
