class CreateBeverages < ActiveRecord::Migration[8.1]
  def change
    create_table :beverages do |t|
      t.string :type, null: false
      t.string :name, null: false
      t.string :description
      t.integer :caffeine_mg
      t.string :roast_level
      t.integer :steep_time_minutes

      t.timestamps
    end

    add_index :beverages, :type
  end
end
