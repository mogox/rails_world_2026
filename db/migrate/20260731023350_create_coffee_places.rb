class CreateCoffeePlaces < ActiveRecord::Migration[8.1]
  def change
    create_table :coffee_places do |t|
      t.string :name
      t.string :address
      t.integer :rating

      t.timestamps
    end
  end
end
