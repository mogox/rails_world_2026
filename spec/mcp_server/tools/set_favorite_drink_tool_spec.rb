require "rails_helper"
require_relative "../../../mcp_server/tools/set_favorite_drink_tool"

RSpec.describe SetFavoriteDrinkTool do
  it "sets a Coffee as the favorite drink" do
    coffee = Coffee.create!(name: "Pour Over")
    place = CoffeePlace.create!(name: "Blue Bottle", address: "123 Main St")

    response = described_class.call(id: place.id, beverage_type: "Coffee", beverage_id: coffee.id)

    expect(response.error?).to be(false)
    expect(place.reload.favorite_drink).to eq(coffee)
  end

  it "sets a Tea as the favorite drink" do
    tea = Tea.create!(name: "Sencha")
    place = CoffeePlace.create!(name: "Blue Bottle", address: "123 Main St")

    response = described_class.call(id: place.id, beverage_type: "Tea", beverage_id: tea.id)

    expect(response.error?).to be(false)
    expect(place.reload.favorite_drink).to eq(tea)
  end

  it "clears the favorite drink when no beverage is given" do
    coffee = Coffee.create!(name: "Pour Over")
    place = CoffeePlace.create!(name: "Blue Bottle", address: "123 Main St", favorite_drink: coffee)

    response = described_class.call(id: place.id)

    expect(response.error?).to be(false)
    expect(place.reload.favorite_drink).to be_nil
  end

  it "clears the favorite drink when beverage_type and beverage_id are explicitly nil" do
    coffee = Coffee.create!(name: "Pour Over")
    place = CoffeePlace.create!(name: "Blue Bottle", address: "123 Main St", favorite_drink: coffee)

    response = described_class.call(id: place.id, beverage_type: nil, beverage_id: nil)

    expect(response.error?).to be(false)
    expect(place.reload.favorite_drink).to be_nil
  end

  it "ignores a disallowed beverage type instead of persisting it" do
    place = CoffeePlace.create!(name: "Blue Bottle", address: "123 Main St")

    response = described_class.call(id: place.id, beverage_type: "Foo", beverage_id: 1)

    expect(response.error?).to be(false)
    expect(place.reload.favorite_drink).to be_nil
  end

  it "returns an error response when the coffee place does not exist" do
    response = described_class.call(id: -1)

    expect(response.error?).to be(true)
    expect(response.content.first[:text]).to include("No coffee place found")
  end
end
