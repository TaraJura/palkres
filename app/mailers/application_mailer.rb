class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("ORDER_MAIL_FROM", "Palkres <objednavky@palkres.cz>"),
          reply_to: ENV.fetch("ORDER_MAIL_REPLY_TO", "info@palkres.cz")
  layout "mailer"

  helper ApplicationHelper
end
