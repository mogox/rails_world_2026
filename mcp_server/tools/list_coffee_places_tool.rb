# frozen_string_literal: true

class ListCoffeePlacesTool < MCP::Tool
  tool_name "list_coffee_places"
  title "List Coffee Places"
  description "Lists all coffee places with their address and rating"
  input_schema(properties: {}, required: [])

  class << self
    def call
      places = CoffeePlace.order(:id)

      text = places.none? ? "No coffee places yet." : places.map { |place| summarize(place) }.join("\n")

      MCP::Tool::Response.new([{ type: "text", text: text }])
    end

    private

    def summarize(place)
      rating = place.rating ? " (rating: #{place.rating}/5)" : ""
      "#{place.id}: #{place.name} — #{place.address}#{rating}"
    end
  end
end
