class Category < ApplicationRecord
  has_ancestry cache_depth: true

  extend FriendlyId
  friendly_id :slug_candidates, use: :slugged

  has_many :product_categories, dependent: :destroy
  has_many :products, through: :product_categories

  validates :name, presence: true
  validates :external_path, uniqueness: true, allow_nil: true

  scope :roots_sorted, -> { roots.order(:name) }

  SEPARATOR = " / ".freeze

  def self.find_or_create_from_path(path_string)
    parts = path_string.to_s.split(SEPARATOR).map(&:strip).reject(&:empty?)
    return nil if parts.empty?

    parent = nil
    cumulative = []
    parts.each do |part|
      cumulative << part
      external = cumulative.join(SEPARATOR)
      node = find_by(external_path: external) ||
             create!(name: part, parent: parent, external_path: external)
      parent = node
    end
    parent
  end

  def slug_candidates
    [
      name,
      [parent&.name, name].compact.join("-"),
      external_path
    ]
  end

  def breadcrumb
    path_ids.present? ? self.class.where(id: path_ids).order(:ancestry) : [self]
  end
end
