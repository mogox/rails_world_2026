# frozen_string_literal: true

require_relative "tools/list_coffee_places_tool"
require_relative "tools/coffee_place_card_tool"
require_relative "tools/rate_coffee_place_tool"
require_relative "tools/set_favorite_drink_tool"

module McpServer
  # RFC 6570 level-1 template; the `mcp` gem matches `{id}` against one path
  # segment and hands `contents` the captured value.
  CARD_URI_TEMPLATE = "#{CoffeePlaceCardTool::CARD_URI_PREFIX}{id}"

  def self.build
    server = MCP::Server.new(
      name: "coffee_spots_mcp",
      title: "Coffee Spots MCP Server",
      version: "1.0.0",
      capabilities: capabilities,
      tools: [ListCoffeePlacesTool, CoffeePlaceCardTool, RateCoffeePlaceTool, SetFavoriteDrinkTool],
    )

    register_card_resources(server)

    server
  end

  def self.capabilities
    caps = MCP::Server::Capabilities.new
    caps.support_tools
    caps.support_resources
    caps.support_extensions(MCP::Apps.capability)
    caps
  end

  def self.register_card_resources(server)
    server.define_resource(
      uri: CoffeePlaceCardTool::TEMPLATE_URI,
      name: "coffee_place_card_template",
      mime_type: MCP::Apps::RESOURCE_MIME_TYPE,
    ) do
      MCP::Resource::TextContents.new(
        uri: CoffeePlaceCardTool::TEMPLATE_URI,
        mime_type: MCP::Apps::RESOURCE_MIME_TYPE,
        text: CoffeePlaceCardTool.template_html,
      )
    end

    server.define_resource_template(
      uri_template: CARD_URI_TEMPLATE,
      name: "coffee_place_card",
      mime_type: MCP::Apps::RESOURCE_MIME_TYPE,
    ) do |id:|
      MCP::Resource::TextContents.new(
        uri: "#{CoffeePlaceCardTool::CARD_URI_PREFIX}#{id}",
        mime_type: MCP::Apps::RESOURCE_MIME_TYPE,
        text: CoffeePlaceCardTool.card_html_for(id) || CoffeePlaceCardTool.not_found_html(id),
      )
    end
  end

  def self.rack_app(server = build)
    MCP::Server::Transports::StreamableHTTPTransport.new(server)
  end
end
