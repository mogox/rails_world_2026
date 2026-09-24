class AddFavoriteDrinkToCoffeePlaces < ActiveRecord::Migration[8.1]
  def change
    add_reference :coffee_places, :favorite_drink, polymorphic: true, null: true
  end
end
