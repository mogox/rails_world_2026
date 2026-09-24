require "rails_helper"
require_relative "../../mcp_server/server"

RSpec.describe "McpServer" do
  def read_resource(server, uri)
    response = server.handle({ jsonrpc: "2.0", id: 1, method: "resources/read", params: { uri: uri } })
    expect(response[:error]).to be_nil, "resources/read failed: #{response[:error].inspect}"
    response.dig(:result, :contents)
  end

  it "registers all four coffee place tools" do
    server = McpServer.build

    expect(server.tools.keys).to match_array(["list_coffee_places", "get_coffee_place_card", "rate_coffee_place", "set_favorite_drink"])
  end

  it "builds a Streamable HTTP Rack app from a server" do
    rack_app = McpServer.rack_app(McpServer.build)

    expect(rack_app).to respond_to(:call)
  end

  it "declares the MCP Apps extension alongside tools and resources" do
    capabilities = McpServer.build.capabilities.to_h

    expect(capabilities[:tools]).to eq({})
    expect(capabilities[:resources]).to eq({})
    expect(capabilities[:extensions]).to eq(
      "io.modelcontextprotocol/ui" => { mimeTypes: ["text/html;profile=mcp-app"] },
    )
  end

  it "registers the static UI template resource the card tool links to" do
    resource = McpServer.build.resources.find { |r| r.uri == CoffeePlaceCardTool::TEMPLATE_URI }

    expect(resource).not_to be_nil
    expect(resource.mime_type).to eq("text/html;profile=mcp-app")
  end

  it "serves the shell document when the template resource is read" do
    server = McpServer.build

    contents = read_resource(server, CoffeePlaceCardTool::TEMPLATE_URI)

    expect(contents.first[:uri]).to eq(CoffeePlaceCardTool::TEMPLATE_URI)
    expect(contents.first[:mimeType]).to eq("text/html;profile=mcp-app")
    expect(contents.first[:text]).to include("card-shell")
  end

  it "serves the per-place card through the ui://coffee-place-card/{id} resource template" do
    place = CoffeePlace.create!(name: "Blue Bottle", address: "123 Main St", rating: 4)
    server = McpServer.build

    contents = read_resource(server, "ui://coffee-place-card/#{place.id}")

    expect(contents.first[:uri]).to eq("ui://coffee-place-card/#{place.id}")
    expect(contents.first[:mimeType]).to eq("text/html;profile=mcp-app")
    expect(contents.first[:text]).to include("Blue Bottle")
    expect(contents.first[:text]).to include("123 Main St")
  end

  it "serves the same HTML through the resource template as the tool embeds" do
    place = CoffeePlace.create!(name: "Philz Coffee", address: "456 Elm St")
    server = McpServer.build

    from_template = read_resource(server, "ui://coffee-place-card/#{place.id}").first[:text]
    from_tool = CoffeePlaceCardTool.call(id: place.id).content.first[:resource][:text]

    expect(from_template).to eq(from_tool)
  end

  it "returns a readable not-found document rather than raising for an unknown id" do
    server = McpServer.build

    contents = read_resource(server, "ui://coffee-place-card/999999")

    expect(contents.first[:mimeType]).to eq("text/html;profile=mcp-app")
    expect(contents.first[:text]).to include("No coffee place found")
  end
end
