# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_07_000002) do
  create_table "beverages", force: :cascade do |t|
    t.integer "caffeine_mg"
    t.datetime "created_at", null: false
    t.string "description"
    t.string "name", null: false
    t.string "roast_level"
    t.integer "steep_time_minutes"
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.index ["type"], name: "index_beverages_on_type"
  end

  create_table "coffee_places", force: :cascade do |t|
    t.string "address"
    t.datetime "created_at", null: false
    t.integer "favorite_drink_id"
    t.string "favorite_drink_type"
    t.string "name"
    t.integer "rating"
    t.datetime "updated_at", null: false
    t.index ["favorite_drink_type", "favorite_drink_id"], name: "index_coffee_places_on_favorite_drink"
  end
end
