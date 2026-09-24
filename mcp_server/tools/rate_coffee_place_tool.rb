# frozen_string_literal: true

class RateCoffeePlaceTool < MCP::Tool
  tool_name "rate_coffee_place"
  title "Rate Coffee Place"
  description "Updates a coffee place's star rating"
  input_schema(
    properties: {
      id: { type: "integer", description: "The coffee place's id" },
      rating: { type: "integer", description: "New rating, 1-5" },
    },
    required: ["id", "rating"],
  )

  class << self
    def call(id:, rating:)
      place = CoffeePlace.find_by(id: id)
      return not_found_response(id) unless place

      place.rating = rating

      if place.save
        MCP::Tool::Response.new([{ type: "text", text: "Rating updated" }])
      else
        MCP::Tool::Response.new([{ type: "text", text: place.errors.full_messages.to_sentence }], error: true)
      end
    end

    private

    def not_found_response(id)
      MCP::Tool::Response.new([{ type: "text", text: "No coffee place found with id #{id}" }], error: true)
    end
  end
end
