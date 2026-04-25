MoneyRails.configure do |config|
  config.default_currency = :czk
  config.rounding_mode = BigDecimal::ROUND_HALF_UP
end

Money.locale_backend = :i18n
Money.default_formatting_rules = { sign_before_symbol: false, decimal_mark: ",", thousands_separator: " ", symbol: "Kč", format: "%n %u" }
