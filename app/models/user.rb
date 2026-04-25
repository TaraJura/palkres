class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :addresses, dependent: :destroy
  has_many :orders, dependent: :nullify
  has_many :carts, dependent: :destroy

  enum :role, { customer: 0, dealer: 1, admin: 2 }, default: :customer

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }

  def full_name
    [first_name, last_name].compact_blank.join(" ").presence || email_address
  end
end
