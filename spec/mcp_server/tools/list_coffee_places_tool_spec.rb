require "rails_helper"
require_relative "../../../mcp_server/tools/list_coffee_places_tool"

RSpec.describe ListCoffeePlacesTool do
  it "lists coffee places with their address and rating" do
    CoffeePlace.create!(name: "Blue Bottle", address: "123 Main St", rating: 5)
    CoffeePlace.create!(name: "Ritual", address: "456 Elm St")

    response = described_class.call
    text = response.content.first[:text]

    expect(response.error?).to be(false)
    expect(text).to include("Blue Bottle — 123 Main St (rating: 5/5)")
    expect(text).to include("Ritual — 456 Elm St")
  end

  it "reports when there are no coffee places" do
    response = described_class.call

    expect(response.content.first[:text]).to eq("No coffee places yet.")
  end
end
