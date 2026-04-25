class Shipment < ApplicationRecord
  belongs_to :order

  STATUSES = %w[pending label_printed handed_over delivered].freeze
  validates :status, inclusion: { in: STATUSES }
end
