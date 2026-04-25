class Payment < ApplicationRecord
  belongs_to :order

  STATUSES = %w[pending authorized paid refunded failed].freeze
  validates :status, inclusion: { in: STATUSES }

  monetize :amount_cents, as: :amount, with_model_currency: :currency
end
