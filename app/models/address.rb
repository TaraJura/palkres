class Address < ApplicationRecord
  belongs_to :user

  enum :kind, { billing: 0, shipping: 1 }

  validates :street, :city, :postal_code, :country_code, presence: true
end
