require "rails_helper"
require_relative "../../../mcp_server/tools/rate_coffee_place_tool"

RSpec.describe RateCoffeePlaceTool do
  it "updates the coffee place's rating" do
    place = CoffeePlace.create!(name: "Blue Bottle", address: "123 Main St", rating: 2)

    response = described_class.call(id: place.id, rating: 5)

    expect(response.error?).to be(false)
    expect(response.content.first[:text]).to eq("Rating updated")
    expect(place.reload.rating).to eq(5)
  end

  it "returns a validation error for an out-of-range rating and leaves the record unchanged" do
    place = CoffeePlace.create!(name: "Blue Bottle", address: "123 Main St", rating: 2)

    response = described_class.call(id: place.id, rating: 9)

    expect(response.error?).to be(true)
    expect(response.content.first[:text]).to include("Rating")
    expect(place.reload.rating).to eq(2)
  end

  it "returns an error response when the coffee place does not exist" do
    response = described_class.call(id: -1, rating: 3)

    expect(response.error?).to be(true)
    expect(response.content.first[:text]).to include("No coffee place found")
  end
end
