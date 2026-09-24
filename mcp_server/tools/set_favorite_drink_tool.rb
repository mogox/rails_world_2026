# frozen_string_literal: true

class SetFavoriteDrinkTool < MCP::Tool
  tool_name "set_favorite_drink"
  title "Set Favorite Drink"
  description "Sets or clears a coffee place's favorite drink"
  input_schema(
    properties: {
      id: { type: "integer", description: "The coffee place's id" },
      beverage_type: { type: ["string", "null"], description: "\"Coffee\" or \"Tea\"; omit or null to clear" },
      beverage_id: { type: ["integer", "null"], description: "The beverage's id; omit or null to clear" },
    },
    required: ["id"],
  )

  ALLOWED_TYPES = %w[Coffee Tea].freeze

  class << self
    def call(id:, beverage_type: nil, beverage_id: nil)
      place = CoffeePlace.find_by(id: id)
      return not_found_response(id) unless place

      place.favorite_drink = resolve_beverage(beverage_type, beverage_id)

      if place.save
        MCP::Tool::Response.new([{ type: "text", text: "Favorite drink updated" }])
      else
        MCP::Tool::Response.new([{ type: "text", text: place.errors.full_messages.to_sentence }], error: true)
      end
    end

    private

    def resolve_beverage(beverage_type, beverage_id)
      return nil unless ALLOWED_TYPES.include?(beverage_type) && beverage_id.present?

      beverage_type.constantize.find_by(id: beverage_id)
    end

    def not_found_response(id)
      MCP::Tool::Response.new([{ type: "text", text: "No coffee place found with id #{id}" }], error: true)
    end
  end
end
