class OrderMailer < ApplicationMailer
  def confirmation(order_id)
    @order = Order.find(order_id)
    @confirmation_url = order_confirmation_url(
      number: @order.number,
      token: @order.confirmation_token,
      host: ENV.fetch("APP_HOST", "palkres.techtools.cz"),
      protocol: "https"
    )

    if @order.payment_method == "bank_transfer" && Payments::CzechQr.available?
      @qr_payload, qr_svg = Payments::CzechQr.for_order(@order)
      attachments.inline["payment-qr.svg"] = { mime_type: "image/svg+xml", content: qr_svg }
    end

    bcc = ENV["ORDER_MAIL_BCC"].presence
    mail(
      to: @order.email,
      bcc: bcc,
      subject: "Potvrzení objednávky #{@order.number} — Palkres"
    )
  end
end
