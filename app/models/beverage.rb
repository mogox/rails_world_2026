class Beverage < ApplicationRecord
  validates :name, presence: true

  has_many :coffee_places, as: :favorite_drink, dependent: :nullify

  # Polymorphic type columns default to base_class.name ("Beverage") for STI
  # subclasses. The form's encoded option values (and thus the controller's
  # assign_favorite_drink) use the STI subclass name ("Coffee"/"Tea") instead —
  # override so both paths write the same value.
  def self.polymorphic_name
    name
  end
end
