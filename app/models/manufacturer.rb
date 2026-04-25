class Manufacturer < ApplicationRecord
  extend FriendlyId
  friendly_id :name, use: :slugged

  has_many :products, dependent: :restrict_with_exception

  validates :name, presence: true, uniqueness: true
end
