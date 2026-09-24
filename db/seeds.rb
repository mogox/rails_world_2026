# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

Coffee.find_or_create_by!(name: "Pour Over") do |coffee|
  coffee.description = "Hand-poured, single origin"
  coffee.caffeine_mg = 95
  coffee.roast_level = "light"
end

Coffee.find_or_create_by!(name: "Espresso") do |coffee|
  coffee.description = "Double shot"
  coffee.caffeine_mg = 63
  coffee.roast_level = "dark"
end

Tea.find_or_create_by!(name: "Sencha") do |tea|
  tea.description = "Japanese green tea"
  tea.caffeine_mg = 25
  tea.steep_time_minutes = 2
end

Tea.find_or_create_by!(name: "Earl Grey") do |tea|
  tea.description = "Black tea with bergamot"
  tea.caffeine_mg = 40
  tea.steep_time_minutes = 4
end

# Real San Francisco coffee shops, used as demo data for the MCP-UI card (see
# mcp_server/tools/coffee_place_card_tool.rb's LOGOS/ACCENTS, keyed on these
# exact names). Left unrated with no favorite drink so every demo run starts
# fresh for the live rating/favorite-drink interactions.
{
  "Blue Bottle" => "315 Linden St",
  "Ritual Coffee Roasters" => "1026 Valencia St",
  "Saint Frank Coffee" => "2340 Polk St",
  "Sightglass Coffee" => "270 7th St",
  "Philz Coffee" => "3101 24th St",
}.each do |name, address|
  CoffeePlace.find_or_create_by!(name: name) do |coffee_place|
    coffee_place.address = address
  end
end
