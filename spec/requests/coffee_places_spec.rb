require 'rails_helper'

RSpec.describe "CoffeePlaces", type: :request do
  describe "GET /coffee_places" do
    it "lists existing coffee places" do
      CoffeePlace.create!(name: "Blue Bottle", address: "123 Main St", rating: 5)

      get coffee_places_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Blue Bottle")
      expect(response.body).to include("123 Main St")
    end

    it "does not include the add-a-place form" do
      get coffee_places_path

      expect(response.body).not_to include("Add place")
    end
  end

  describe "GET /coffee_places/new" do
    it "renders the add-a-place form" do
      get new_coffee_place_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Add a coffee place")
    end
  end

  describe "POST /coffee_places" do
    it "creates a coffee place with valid attributes" do
      expect {
        post coffee_places_path, params: { coffee_place: { name: "Ritual", address: "456 Elm St", rating: 4 } }
      }.to change(CoffeePlace, :count).by(1)

      expect(response).to redirect_to(coffee_places_path)
    end

    it "does not create a coffee place with invalid attributes" do
      expect {
        post coffee_places_path, params: { coffee_place: { name: "", address: "" } }
      }.not_to change(CoffeePlace, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Add a coffee place")
    end

    it "ignores a favorite_drink value with an unrecognized type instead of persisting it" do
      post coffee_places_path, params: { coffee_place: { name: "X", address: "Y", favorite_drink: "Foo-1" } }

      expect(CoffeePlace.last.favorite_drink).to be_nil
      get root_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /coffee_places/:id" do
    let(:place) { CoffeePlace.create!(name: "Blue Bottle", address: "123 Main St", rating: 4) }

    it "renders the MCP-UI card in a sandboxed iframe when the MCP server responds" do
      fake_client = instance_double(Mcp::Client, coffee_place_card: "<h2>Blue Bottle</h2>")
      allow(Mcp::Client).to receive(:new).and_return(fake_client)

      get coffee_place_path(place)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<iframe")
      expect(response.body).to include('sandbox="allow-scripts"')
      expect(response.body).to include('id="coffee-place-card"')
      expect(response.body).to include("mcp_action")
      # The card's srcdoc is fully replaced between sendAction and the reply (see
      # mcp_server/tools/coffee_place_card_tool.rb), so every reply must carry the
      # tool name/params itself rather than relying on the card's prior script state.
      # All 3 reply sites (success, HTTP error, network error) must include them.
      expect(response.body.scan("toolName: toolName, params: params").length).to eq(3)
      expect(fake_client).to have_received(:coffee_place_card).with(place.id)
    end

    it "falls back to plain attributes when the MCP server is unreachable" do
      fake_client = instance_double(Mcp::Client)
      allow(Mcp::Client).to receive(:new).and_return(fake_client)
      allow(fake_client).to receive(:coffee_place_card).and_raise(Mcp::Client::ConnectionError, "connection refused")

      get coffee_place_path(place)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Live card unavailable")
      expect(response.body).to include("123 Main St")
    end
  end

  describe "POST /coffee_places/:id/mcp_action" do
    let(:place) { CoffeePlace.create!(name: "Blue Bottle", address: "123 Main St", rating: 4) }

    it "relays an allowlisted action to Mcp::Client and returns the refreshed card" do
      fake_client = instance_double(Mcp::Client, call_action: "<h2>Blue Bottle</h2>")
      allow(Mcp::Client).to receive(:new).and_return(fake_client)

      post mcp_action_coffee_place_path(place), params: { tool_name: "rate_coffee_place", params: { rating: 5 } }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["html"]).to eq("<h2>Blue Bottle</h2>")
      expect(fake_client).to have_received(:call_action).with("rate_coffee_place", { rating: 5, id: place.id })
    end

    it "ignores an id in the body and always scopes the action to the URL's coffee place" do
      other_place = CoffeePlace.create!(name: "Other Place", address: "999 Other St", rating: 1)
      fake_client = instance_double(Mcp::Client, call_action: "<h2>Blue Bottle</h2>")
      allow(Mcp::Client).to receive(:new).and_return(fake_client)

      post mcp_action_coffee_place_path(place), params: { tool_name: "rate_coffee_place", params: { id: other_place.id, rating: 5 } }, as: :json

      expect(response).to have_http_status(:ok)
      expect(fake_client).to have_received(:call_action).with("rate_coffee_place", { id: place.id, rating: 5 })
    end

    it "rejects a tool_name that is not allowlisted" do
      expect(Mcp::Client).not_to receive(:new)

      post mcp_action_coffee_place_path(place), params: { tool_name: "delete_everything", params: {} }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("Unknown action")
    end

    it "returns an error body when the MCP action fails" do
      fake_client = instance_double(Mcp::Client)
      allow(Mcp::Client).to receive(:new).and_return(fake_client)
      allow(fake_client).to receive(:call_action).and_raise(Mcp::Client::ToolError, "Rating is not included in the list")

      post mcp_action_coffee_place_path(place), params: { tool_name: "rate_coffee_place", params: { rating: 9 } }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("Rating is not included in the list")
    end
  end
end
