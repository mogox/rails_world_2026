require "rails_helper"

RSpec.describe Mcp::Client do
  describe "#coffee_place_card" do
    it "returns the card HTML from a text-encoded resource" do
      fake_transport = instance_double("MCP::Client::HTTP", close: nil, connected?: true)
      fake_mcp_client = instance_double(
        MCP::Client,
        connect: nil,
        transport: fake_transport,
        call_tool: {
          "jsonrpc" => "2.0",
          "id" => 1,
          "result" => {
            "content" => [
              { "type" => "resource", "resource" => { "uri" => "ui://coffee-place-card/1", "mimeType" => "text/html", "text" => "<h2>Blue Bottle</h2>" } },
            ],
            "isError" => false,
          },
        },
      )
      client = described_class.new(mcp_client: fake_mcp_client)

      html = client.coffee_place_card(1)

      expect(html).to eq("<h2>Blue Bottle</h2>")
      expect(fake_mcp_client).to have_received(:call_tool).with(name: "get_coffee_place_card", arguments: { id: 1 })
    end

    it "base64-decodes a blob-encoded resource" do
      encoded = Base64.strict_encode64("<h2>Ritual</h2>")
      fake_transport = instance_double("MCP::Client::HTTP", close: nil, connected?: true)
      fake_mcp_client = instance_double(
        MCP::Client,
        connect: nil,
        transport: fake_transport,
        call_tool: {
          "jsonrpc" => "2.0",
          "id" => 2,
          "result" => {
            "content" => [
              { "type" => "resource", "resource" => { "uri" => "ui://coffee-place-card/2", "mimeType" => "text/html", "blob" => encoded } },
            ],
            "isError" => false,
          },
        },
      )
      client = described_class.new(mcp_client: fake_mcp_client)

      expect(client.coffee_place_card(2)).to eq("<h2>Ritual</h2>")
    end

    it "raises ToolError when a resource has neither text nor blob" do
      fake_transport = instance_double("MCP::Client::HTTP", close: nil, connected?: true)
      fake_mcp_client = instance_double(
        MCP::Client,
        connect: nil,
        transport: fake_transport,
        call_tool: {
          "jsonrpc" => "2.0",
          "id" => 3,
          "result" => {
            "content" => [
              { "type" => "resource", "resource" => { "uri" => "ui://coffee-place-card/3", "mimeType" => "text/html" } },
            ],
            "isError" => false,
          },
        },
      )
      client = described_class.new(mcp_client: fake_mcp_client)

      expect { client.coffee_place_card(3) }.to raise_error(Mcp::Client::ToolError, /Coffee place card resource has neither text nor blob content/)
    end

    it "raises ToolError when the tool reports an error" do
      fake_transport = instance_double("MCP::Client::HTTP", close: nil, connected?: true)
      fake_mcp_client = instance_double(
        MCP::Client,
        connect: nil,
        transport: fake_transport,
        call_tool: {
          "jsonrpc" => "2.0",
          "id" => 4,
          "result" => {
            "content" => [{ "type" => "text", "text" => "No coffee place found with id 99" }],
            "isError" => true,
          },
        },
      )
      client = described_class.new(mcp_client: fake_mcp_client)

      expect { client.coffee_place_card(99) }.to raise_error(Mcp::Client::ToolError, /No coffee place found with id 99/)
    end

    it "raises ConnectionError when the MCP server is unreachable" do
      fake_transport = instance_double("MCP::Client::HTTP", close: nil, connected?: false)
      fake_mcp_client = instance_double(MCP::Client, transport: fake_transport)
      allow(fake_mcp_client).to receive(:connect).and_raise(MCP::Client::RequestHandlerError.new("Connection failed", nil))
      client = described_class.new(mcp_client: fake_mcp_client)

      expect { client.coffee_place_card(1) }.to raise_error(Mcp::Client::ConnectionError, /localhost:3001/)
    end

    it "raises ToolError (not ConnectionError) when the server returns a JSON-RPC error" do
      fake_transport = instance_double("MCP::Client::HTTP", close: nil, connected?: true)
      fake_mcp_client = instance_double(MCP::Client, connect: nil, transport: fake_transport)
      allow(fake_mcp_client).to receive(:call_tool)
        .and_raise(MCP::Client::ServerError.new("Internal error", code: -32603, data: nil))
      client = described_class.new(mcp_client: fake_mcp_client)

      expect { client.coffee_place_card(1) }.to raise_error(Mcp::Client::ToolError, /Internal error/)
    end
  end

  describe "#call_action" do
    it "calls the write tool, then re-fetches and returns the refreshed card" do
      fake_transport = instance_double("MCP::Client::HTTP", close: nil, connected?: true)
      fake_mcp_client = instance_double(MCP::Client, connect: nil, transport: fake_transport)
      allow(fake_mcp_client).to receive(:call_tool)
        .with(name: "rate_coffee_place", arguments: { id: 1, rating: 5 })
        .and_return({ "result" => { "content" => [{ "type" => "text", "text" => "Rating updated" }], "isError" => false } })
      allow(fake_mcp_client).to receive(:call_tool)
        .with(name: "get_coffee_place_card", arguments: { id: 1 })
        .and_return({ "result" => { "content" => [{ "type" => "resource", "resource" => { "uri" => "ui://coffee-place-card/1", "mimeType" => "text/html", "text" => "<h2>Blue Bottle</h2>" } }], "isError" => false } })
      client = described_class.new(mcp_client: fake_mcp_client)

      html = client.call_action("rate_coffee_place", { id: 1, rating: 5 })

      expect(html).to eq("<h2>Blue Bottle</h2>")
    end

    it "raises ToolError without re-fetching when the write tool itself errors" do
      fake_transport = instance_double("MCP::Client::HTTP", close: nil, connected?: true)
      fake_mcp_client = instance_double(MCP::Client, connect: nil, transport: fake_transport)
      allow(fake_mcp_client).to receive(:call_tool)
        .with(name: "rate_coffee_place", arguments: { id: 1, rating: 9 })
        .and_return({ "result" => { "content" => [{ "type" => "text", "text" => "Rating is not included in the list" }], "isError" => true } })
      client = described_class.new(mcp_client: fake_mcp_client)

      expect { client.call_action("rate_coffee_place", { id: 1, rating: 9 }) }.to raise_error(Mcp::Client::ToolError, /Rating is not included in the list/)
      expect(fake_mcp_client).not_to have_received(:call_tool).with(name: "get_coffee_place_card", arguments: anything)
    end

    it "raises ToolError when the write succeeds but the refetch fails" do
      fake_transport = instance_double("MCP::Client::HTTP", close: nil, connected?: true)
      fake_mcp_client = instance_double(MCP::Client, connect: nil, transport: fake_transport)
      allow(fake_mcp_client).to receive(:call_tool)
        .with(name: "rate_coffee_place", arguments: { id: 1, rating: 5 })
        .and_return({ "result" => { "content" => [{ "type" => "text", "text" => "Rating updated" }], "isError" => false } })
      allow(fake_mcp_client).to receive(:call_tool)
        .with(name: "get_coffee_place_card", arguments: { id: 1 })
        .and_return({ "result" => { "content" => [{ "type" => "text", "text" => "No coffee place found with id 1" }], "isError" => true } })
      client = described_class.new(mcp_client: fake_mcp_client)

      expect { client.call_action("rate_coffee_place", { id: 1, rating: 5 }) }.to raise_error(Mcp::Client::ToolError, /No coffee place found with id 1/)
    end
  end
end
