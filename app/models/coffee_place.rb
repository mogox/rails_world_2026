class CoffeePlace < ApplicationRecord
  belongs_to :favorite_drink, polymorphic: true, optional: true

  validates :name, presence: true
  validates :address, presence: true
  validates :rating, inclusion: { in: 1..5 }, allow_nil: true
end
