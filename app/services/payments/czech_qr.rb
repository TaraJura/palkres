require "rqrcode"

module Payments
  # Builds a Czech "QR Platba" (SPAYD 1.0) payload for an Order and renders it
  # as an inline-friendly SVG. Banking apps (Air Bank, ČS, KB, Raiffeisen, …)
  # all read SPAYD via their phone-camera "naskenuj a zaplať" feature.
  #
  # Spec reference: https://qr-platba.cz/pro-vyvojare/specifikace-formatu/
  # Format: SPD*1.0*ACC:<IBAN>*AM:<amount>*CC:<currency>*MSG:<msg>*X-VS:<vs>
  class CzechQr
    # Known-bogus IBANs that earlier change-log entries shipped as placeholders.
    # available? returns false for these so a regression in .env can't push
    # a fake account onto a real customer's confirmation page or e-mail.
    PLACEHOLDER_IBANS = %w[CZ6508000000192000145399].freeze

    def self.iban
      ENV.fetch("PALKRES_BANK_IBAN", "").gsub(/\s+/, "")
    end

    def self.beneficiary_name
      ENV.fetch("PALKRES_BANK_NAME", "Palkres s.r.o.")
    end

    def self.placeholder?
      PLACEHOLDER_IBANS.include?(iban)
    end

    def self.available?
      iban.match?(/\A[A-Z]{2}\d{2}[A-Z0-9]{10,30}\z/) && !placeholder?
    end

    # Returns [spayd_string, svg_string] for the given Order. Caller embeds the SVG.
    def self.for_order(order)
      payload = spayd_for(order)
      svg = RQRCode::QRCode.new(payload, level: :m)
                           .as_svg(module_size: 4, standalone: true,
                                   use_path: true, color: "000",
                                   shape_rendering: "crispEdges",
                                   viewbox: true)
      [payload, svg]
    end

    def self.spayd_for(order)
      vs     = order.number.to_s.delete("^0-9")[0, 10]
      amount = format("%.2f", (order.total_cents.to_i / 100.0))
      msg    = sanitize_msg("Palkres #{order.number}")
      parts = [
        "SPD*1.0",
        "ACC:#{iban}",
        "AM:#{amount}",
        "CC:#{(order.currency.presence || 'CZK').upcase}",
        "X-VS:#{vs}",
        "MSG:#{msg}",
        "RN:#{sanitize_msg(beneficiary_name)}"
      ]
      parts.join("*")
    end

    # SPAYD restricts charset; collapse anything risky.
    def self.sanitize_msg(str)
      str.to_s
         .unicode_normalize(:nfkd)
         .gsub(/[^A-Za-z0-9 \-_.,]/, "")
         .strip[0, 60]
    end
  end
end
