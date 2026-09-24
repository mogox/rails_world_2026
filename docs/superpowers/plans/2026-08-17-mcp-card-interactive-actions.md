# MCP-UI Card Interactive Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user submit a new star rating or change the favorite drink directly from the MCP-UI coffee place card, with the change round-tripping through two new MCP write tools — not a Rails-only shortcut.

**Architecture:** Card (sandboxed iframe) → `postMessage` → Rails host JS → `POST /coffee_places/:id/mcp_action` (allowlisted `tool_name`) → `Mcp::Client#call_action` (calls the write tool, then re-fetches `get_coffee_place_card`) → host swaps the iframe's `srcdoc` with the fresh card → posts a `tool-result` reply into the reloaded iframe → the card's own script shows a "Saved via MCP ✓" toast.

**Tech Stack:** Ruby, rspec-rails, vanilla JS (no bundler/asset pipeline involvement — all JS is inline in server-rendered HTML strings), matches the rest of this branch.

## Global Constraints

- Two new MCP tools only: `rate_coffee_place`, `set_favorite_drink`. No other new tools/resources.
- The Rails endpoint (`POST /coffee_places/:id/mcp_action`) MUST allowlist `tool_name` against exactly `%w[rate_coffee_place set_favorite_drink]` server-side before ever touching `Mcp::Client` — this is a hard security requirement (the sandboxed iframe's message is untrusted input to the host).
- The sandboxed iframe keeps `sandbox="allow-scripts"` with no `allow-same-origin` (unchanged from the original plan) — it never makes a network request itself, only `postMessage`s its parent.
- `Mcp::Client`'s existing public behavior (`#coffee_place_card`, its exception classes, its `#coffee_place_card` spec's 5 existing examples) must keep passing unchanged after the `with_connected_client` refactor — this is a refactor, not a behavior change, for that method.
- Match existing conventions: plain `ModelName.create!` in specs, `require "rails_helper"`, the `"Coffee-<id>"`/`"Tea-<id>"` encoded-select-value convention already used in `app/views/coffee_places/new.html.erb` and `CoffeePlacesController#assign_favorite_drink`.
- No new gems, no asset pipeline changes, no DB schema changes.

---

### Task 1: `RateCoffeePlaceTool`

**Files:**
- Create: `mcp_server/tools/rate_coffee_place_tool.rb`
- Test: `spec/mcp_server/tools/rate_coffee_place_tool_spec.rb`

**Interfaces:**
- Consumes: `CoffeePlace` (existing model, `rating` validated `inclusion: { in: 1..5 }, allow_nil: true`).
- Produces: `RateCoffeePlaceTool` (top-level class, `MCP::Tool` subclass), `tool_name` `"rate_coffee_place"`, `.call(id:, rating:)` returning `MCP::Tool::Response` — success: `content` `[{ type: "text", text: "Rating updated" }]`, `error?` false. Validation failure or missing id: `error?` true, `content.first[:text]` explains why. Task 4's controller will call this indirectly via `Mcp::Client#call_action("rate_coffee_place", ...)`.

- [ ] **Step 1: Write the failing spec**

Create `spec/mcp_server/tools/rate_coffee_place_tool_spec.rb`:

```ruby
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/mcp_server/tools/rate_coffee_place_tool_spec.rb`
Expected: FAIL — `uninitialized constant RateCoffeePlaceTool`.

- [ ] **Step 3: Write the tool**

Create `mcp_server/tools/rate_coffee_place_tool.rb`:

```ruby
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
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bundle exec rspec spec/mcp_server/tools/rate_coffee_place_tool_spec.rb`
Expected: PASS (3 examples, 0 failures).

- [ ] **Step 5: Commit**

```bash
git add mcp_server/tools/rate_coffee_place_tool.rb spec/mcp_server/tools/rate_coffee_place_tool_spec.rb
git commit -m "Add rate_coffee_place MCP tool"
```

---

### Task 2: `SetFavoriteDrinkTool`

**Files:**
- Create: `mcp_server/tools/set_favorite_drink_tool.rb`
- Test: `spec/mcp_server/tools/set_favorite_drink_tool_spec.rb`

**Interfaces:**
- Consumes: `CoffeePlace#favorite_drink=` (polymorphic, existing), `Coffee`/`Tea` (existing `Beverage` STI subclasses).
- Produces: `SetFavoriteDrinkTool` (top-level class, `MCP::Tool` subclass), `tool_name` `"set_favorite_drink"`, `.call(id:, beverage_type: nil, beverage_id: nil)` — same success/error `MCP::Tool::Response` shape as Task 1. A disallowed `beverage_type` or missing `beverage_id` clears the favorite drink rather than raising (mirrors `CoffeePlacesController#assign_favorite_drink`'s allowlist).

- [ ] **Step 1: Write the failing spec**

Create `spec/mcp_server/tools/set_favorite_drink_tool_spec.rb`:

```ruby
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/mcp_server/tools/set_favorite_drink_tool_spec.rb`
Expected: FAIL — `uninitialized constant SetFavoriteDrinkTool`.

- [ ] **Step 3: Write the tool**

Create `mcp_server/tools/set_favorite_drink_tool.rb`:

```ruby
# frozen_string_literal: true

class SetFavoriteDrinkTool < MCP::Tool
  tool_name "set_favorite_drink"
  title "Set Favorite Drink"
  description "Sets or clears a coffee place's favorite drink"
  input_schema(
    properties: {
      id: { type: "integer", description: "The coffee place's id" },
      beverage_type: { type: "string", description: "\"Coffee\" or \"Tea\"; omit to clear" },
      beverage_id: { type: "integer", description: "The beverage's id; omit to clear" },
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
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bundle exec rspec spec/mcp_server/tools/set_favorite_drink_tool_spec.rb`
Expected: PASS (5 examples, 0 failures).

- [ ] **Step 5: Commit**

```bash
git add mcp_server/tools/set_favorite_drink_tool.rb spec/mcp_server/tools/set_favorite_drink_tool_spec.rb
git commit -m "Add set_favorite_drink MCP tool"
```

---

### Task 3: `Mcp::Client#call_action` (+ `with_connected_client` refactor)

**Files:**
- Modify: `app/services/mcp/client.rb`
- Modify: `spec/services/mcp/client_spec.rb`

**Interfaces:**
- Consumes: `rate_coffee_place`/`set_favorite_drink` tool names (Tasks 1-2, referenced only as strings — no file dependency), `get_coffee_place_card` (existing).
- Produces: `Mcp::Client#call_action(tool_name, params)` — `params` is a `Hash` that must include `:id`; calls `tool_name` with `params`, raises `Mcp::Client::ToolError` if that call errors, otherwise calls `get_coffee_place_card` with `params[:id]` and returns its HTML `String` the same way `#coffee_place_card` does. Same `ConnectionError`/`ToolError` classes as `#coffee_place_card` — Task 4's controller rescues both from either method identically. `#coffee_place_card`'s public behavior is unchanged.

- [ ] **Step 1: Write the failing spec**

Replace the full contents of `spec/services/mcp/client_spec.rb` with (this preserves all 5 existing `#coffee_place_card` examples unchanged and adds a new `#call_action` describe block):

```ruby
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/services/mcp/client_spec.rb`
Expected: FAIL — the 3 new `#call_action` examples fail with `NoMethodError: undefined method 'call_action'`; the 5 `#coffee_place_card` examples still pass unchanged.

- [ ] **Step 3: Refactor and extend the client**

Replace the full contents of `app/services/mcp/client.rb` with:

```ruby
# frozen_string_literal: true

require "net/http"
require "base64"

module Mcp
  class Client
    class ConnectionError < StandardError; end
    class ToolError < StandardError; end

    def initialize(server_url: ENV.fetch("MCP_SERVER_URL", "http://localhost:3001"), mcp_client: nil)
      @server_url = server_url
      @injected_client = mcp_client
    end

    def coffee_place_card(id)
      with_connected_client do |client|
        envelope = client.call_tool(name: "get_coffee_place_card", arguments: { id: id })
        result = envelope["result"] || {}

        raise ToolError, error_text(result) if result["isError"]

        html(result)
      end
    end

    def call_action(tool_name, params)
      with_connected_client do |client|
        write_envelope = client.call_tool(name: tool_name, arguments: params)
        write_result = write_envelope["result"] || {}

        raise ToolError, error_text(write_result) if write_result["isError"]

        card_envelope = client.call_tool(name: "get_coffee_place_card", arguments: { id: params[:id] })
        card_result = card_envelope["result"] || {}

        raise ToolError, error_text(card_result) if card_result["isError"]

        html(card_result)
      end
    end

    private

    def with_connected_client
      client = mcp_client
      client.connect(client_info: { name: "coffee_spots", version: "1.0" })
      yield client
    rescue MCP::Client::RequestHandlerError, Faraday::Error, Errno::ECONNREFUSED, SocketError => e
      raise ConnectionError, "Could not reach the MCP server at #{@server_url}: #{e.message}"
    ensure
      begin
        client.transport.close if client.transport.respond_to?(:connected?) && client.transport.connected?
      rescue StandardError => e
        Rails.logger.debug("MCP client close failed: #{e.class}: #{e.message}")
      end
    end

    def mcp_client
      @injected_client || MCP::Client.new(transport: MCP::Client::HTTP.new(url: @server_url))
    end

    def html(result)
      resource_item = Array(result["content"]).find { |item| item["type"] == "resource" }
      raise ToolError, "No UI resource returned for coffee place card" unless resource_item

      resource = resource_item["resource"]
      if resource["blob"]
        Base64.decode64(resource["blob"])
      elsif resource["text"]
        resource["text"]
      else
        raise ToolError, "Coffee place card resource has neither text nor blob content"
      end
    end

    def error_text(result)
      text_item = Array(result["content"]).find { |item| item["type"] == "text" }
      text_item ? text_item["text"] : "Unknown MCP tool error"
    end
  end
end
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bundle exec rspec spec/services/mcp/client_spec.rb`
Expected: PASS (8 examples, 0 failures).

- [ ] **Step 5: Commit**

```bash
git add app/services/mcp/client.rb spec/services/mcp/client_spec.rb
git commit -m "Add Mcp::Client#call_action and extract with_connected_client"
```

---

### Task 4: `POST /coffee_places/:id/mcp_action`

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/coffee_places_controller.rb`
- Modify: `spec/requests/coffee_places_spec.rb`

**Interfaces:**
- Consumes: `Mcp::Client#call_action(tool_name, params)` (Task 3).
- Produces: `POST /coffee_places/:id/mcp_action` (route helper `mcp_action_coffee_place_path`), accepting JSON `{ tool_name:, params: {} }`. Responds `{ html: }` (200) on success, `{ error: }` (422) when `tool_name` isn't allowlisted or `Mcp::Client` raises. Task 5/6's card and host JS call this exact route with this exact body shape.

- [ ] **Step 1: Write the failing request spec**

Add to `spec/requests/coffee_places_spec.rb` (after the existing `describe "GET /coffee_places/:id"` block, before the file's final `end`):

```ruby
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/requests/coffee_places_spec.rb`
Expected: FAIL — `undefined method 'mcp_action_coffee_place_path'` (the route doesn't exist yet).

- [ ] **Step 3: Add the route**

In `config/routes.rb`, change:

```ruby
  resources :coffee_places, only: [ :index, :new, :create, :show ]
```

to:

```ruby
  resources :coffee_places, only: [ :index, :new, :create, :show ] do
    member do
      post :mcp_action
    end
  end
```

- [ ] **Step 4: Add the controller action**

In `app/controllers/coffee_places_controller.rb`, add the constant at the top of the class and the action after `show`:

```ruby
class CoffeePlacesController < ApplicationController
  ALLOWED_MCP_ACTIONS = %w[rate_coffee_place set_favorite_drink].freeze

  def index
    @coffee_places = CoffeePlace.preload(:favorite_drink).order(created_at: :desc)
  end

  def show
    @coffee_place = CoffeePlace.find(params[:id])

    begin
      @card_html = Mcp::Client.new.coffee_place_card(@coffee_place.id)
    rescue Mcp::Client::ConnectionError, Mcp::Client::ToolError => e
      Rails.logger.warn("MCP card unavailable for coffee place #{@coffee_place.id}: #{e.class}: #{e.message}")
      @mcp_unavailable = true
    end
  end

  def mcp_action
    tool_name = params[:tool_name].to_s

    unless ALLOWED_MCP_ACTIONS.include?(tool_name)
      return render json: { error: "Unknown action" }, status: :unprocessable_content
    end

    coffee_place = CoffeePlace.find(params[:id])
    action_params = params[:params].is_a?(ActionController::Parameters) ? params[:params].to_unsafe_h.symbolize_keys : {}

    html = Mcp::Client.new.call_action(tool_name, action_params.merge(id: coffee_place.id))
    render json: { html: html }
  rescue Mcp::Client::ConnectionError, Mcp::Client::ToolError => e
    Rails.logger.warn("MCP action #{tool_name} failed for coffee place #{params[:id]}: #{e.class}: #{e.message}")
    render json: { error: e.message }, status: :unprocessable_content
  end

  def new
    @coffee_place = CoffeePlace.new
  end

  def create
    @coffee_place = CoffeePlace.new(coffee_place_params.except(:favorite_drink))
    assign_favorite_drink

    if @coffee_place.save
      redirect_to coffee_places_path, notice: "Coffee place added."
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  def coffee_place_params
    params.expect(coffee_place: [ :name, :address, :rating, :favorite_drink ])
  end

  # The form posts favorite_drink as "Coffee-3"/"Tea-1"/"" (see new.html.erb) rather than
  # separate id/type fields, since a plain <select> can't submit two params from one choice
  # without JS. Split it apart, and only ever assign a real, allowlisted record through the
  # association writer — never write favorite_drink_type/_id directly from unvalidated input,
  # since that lets an arbitrary POST persist a type string that later 500s on constantize.
  def assign_favorite_drink
    type, id = coffee_place_params[:favorite_drink].to_s.split("-", 2)
    return unless %w[Coffee Tea].include?(type) && id.present?

    @coffee_place.favorite_drink = type.constantize.find_by(id: id)
  end
end
```

- [ ] **Step 5: Run it to verify it passes**

Run: `bundle exec rspec spec/requests/coffee_places_spec.rb`
Expected: PASS (all examples, including the 3 new ones).

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/coffee_places_controller.rb spec/requests/coffee_places_spec.rb
git commit -m "Add POST /coffee_places/:id/mcp_action, allowlisted against rate_coffee_place and set_favorite_drink"
```

---

### Task 5: Interactive, styled coffee place card

**Files:**
- Modify: `mcp_server/tools/coffee_place_card_tool.rb`
- Modify: `spec/mcp_server/tools/coffee_place_card_tool_spec.rb`

**Interfaces:**
- Consumes: `Beverage`/`Coffee`/`Tea` (existing), the `rate_coffee_place`/`set_favorite_drink` tool names (Tasks 1-2, referenced only as strings embedded in emitted `onclick`/`onchange` JS — no file dependency).
- Produces: `CoffeePlaceCardTool.call(id:)`'s returned HTML now includes: a colored accent border per shop (reusing each shop's logo color, `DEFAULT_ACCENT` `"#6b7280"` for unknown shops), 5 clickable rating buttons calling `sendAction('rate_coffee_place', {id, rating: N})`, a favorite-drink `<select>` calling `sendAction('set_favorite_drink', {id, beverage_type, beverage_id})` on change, and a toast element/script that shows "Saving…" immediately and "Saved via MCP ✓"/an error message on receiving a `{type: "tool-result"}` `postMessage`. Task 6's host JS is the only thing that posts that reply.

- [ ] **Step 1: Write the failing spec**

Replace the full contents of `spec/mcp_server/tools/coffee_place_card_tool_spec.rb` with:

```ruby
require "rails_helper"
require_relative "../../../mcp_server/tools/coffee_place_card_tool"

RSpec.describe CoffeePlaceCardTool do
  it "returns an MCP-UI resource card for an existing coffee place" do
    coffee = Coffee.create!(name: "Pour Over")
    place = CoffeePlace.create!(name: "Blue Bottle", address: "123 Main St", rating: 4, favorite_drink: coffee)

    response = described_class.call(id: place.id)
    resource_item = response.content.first

    expect(response.error?).to be(false)
    expect(resource_item[:type]).to eq("resource")
    expect(resource_item[:resource][:uri]).to eq("ui://coffee-place-card/#{place.id}")
    expect(resource_item[:resource][:mimeType]).to eq("text/html")
    expect(resource_item[:resource][:text]).to include("Blue Bottle")
    expect(resource_item[:resource][:text]).to include("123 Main St")
    expect(resource_item[:resource][:text]).to include('fill="#2563eb"')
  end

  it "uses a specific logo and accent color for each of the 3 known shop names" do
    e2e = CoffeePlace.create!(name: "E2E Test Coffee", address: "123 Test St")
    live = CoffeePlace.create!(name: "Live Test Coffee", address: "456 Live St")

    e2e_html = described_class.call(id: e2e.id).content.first[:resource][:text]
    live_html = described_class.call(id: live.id).content.first[:resource][:text]

    expect(e2e_html).to include('fill="#16a34a"')
    expect(e2e_html).to include("border-top: 4px solid #16a34a")
    expect(live_html).to include('fill="#c2410c"')
    expect(live_html).to include("border-top: 4px solid #c2410c")
  end

  it "falls back to the default logo and accent color for an unrecognized shop name" do
    place = CoffeePlace.create!(name: "Ritual", address: "456 Elm St")

    html = described_class.call(id: place.id).content.first[:resource][:text]

    expect(html).to include('stroke="#6b7280"')
    expect(html).to include("border-top: 4px solid #6b7280")
  end

  it "renders 5 clickable rating buttons reflecting the current rating" do
    place = CoffeePlace.create!(name: "Ritual", address: "456 Elm St", rating: 3)

    html = described_class.call(id: place.id).content.first[:resource][:text]

    expect(html.scan("sendAction('rate_coffee_place'").length).to eq(5)
    expect(html.scan("★").length).to eq(3)
    expect(html.scan("☆").length).to eq(2)
  end

  it "renders all stars empty when there is no rating yet" do
    place = CoffeePlace.create!(name: "Ritual", address: "456 Elm St")

    html = described_class.call(id: place.id).content.first[:resource][:text]

    expect(html.scan("☆").length).to eq(5)
    expect(html).not_to include("★")
  end

  it "renders a favorite-drink select with the current drink selected" do
    coffee = Coffee.create!(name: "Pour Over")
    place = CoffeePlace.create!(name: "Blue Bottle", address: "123 Main St", favorite_drink: coffee)

    html = described_class.call(id: place.id).content.first[:resource][:text]

    expect(html).to include("<select")
    expect(html).to include("sendAction('set_favorite_drink'")
    expect(html).to include(%(value="Coffee-#{coffee.id}" selected))
  end

  it "renders the favorite-drink select with none selected when there is no favorite drink" do
    place = CoffeePlace.create!(name: "Ritual", address: "456 Elm St")

    html = described_class.call(id: place.id).content.first[:resource][:text]

    expect(html).to include('<option value="" selected>— none —</option>')
  end

  it "returns an error response when the coffee place does not exist" do
    response = described_class.call(id: -1)

    expect(response.error?).to be(true)
    expect(response.content.first[:text]).to include("No coffee place found")
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/mcp_server/tools/coffee_place_card_tool_spec.rb`
Expected: FAIL — the new interactivity/accent/select examples fail (no `sendAction`, no `border-top`, no `<select>` in the current static card); the logo-color examples still pass.

- [ ] **Step 3: Rewrite the tool**

Replace the full contents of `mcp_server/tools/coffee_place_card_tool.rb` with:

```ruby
# frozen_string_literal: true

class CoffeePlaceCardTool < MCP::Tool
  tool_name "get_coffee_place_card"
  title "Get Coffee Place Card"
  description "Returns an MCP-UI HTML card for a single coffee place"
  input_schema(
    properties: { id: { type: "integer", description: "The coffee place's id" } },
    required: ["id"],
  )

  BLUE_BOTTLE_LOGO = <<~SVG.strip
    <svg viewBox="0 0 48 48" width="48" height="48" xmlns="http://www.w3.org/2000/svg">
      <rect x="10" y="10" width="22" height="4" rx="2" fill="#2563eb"/>
      <rect x="10" y="14" width="22" height="20" rx="3" fill="#2563eb"/>
      <path d="M32 18h4a4 4 0 0 1 0 8h-4" fill="none" stroke="#2563eb" stroke-width="3"/>
    </svg>
  SVG

  E2E_TEST_COFFEE_LOGO = <<~SVG.strip
    <svg viewBox="0 0 48 48" width="48" height="48" xmlns="http://www.w3.org/2000/svg">
      <rect x="12" y="10" width="24" height="6" rx="2" fill="#16a34a"/>
      <path d="M14 16h20l-3 20a2 2 0 0 1-2 2H19a2 2 0 0 1-2-2z" fill="#16a34a"/>
    </svg>
  SVG

  LIVE_TEST_COFFEE_LOGO = <<~SVG.strip
    <svg viewBox="0 0 48 48" width="48" height="48" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="24" cy="24" rx="14" ry="20" fill="#c2410c" transform="rotate(20 24 24)"/>
      <path d="M24 6c-4 8-4 28 0 36" fill="none" stroke="#7c2d12" stroke-width="2" transform="rotate(20 24 24)"/>
    </svg>
  SVG

  DEFAULT_LOGO = <<~SVG.strip
    <svg viewBox="0 0 48 48" width="48" height="48" xmlns="http://www.w3.org/2000/svg">
      <rect x="10" y="14" width="22" height="20" rx="3" fill="none" stroke="#6b7280" stroke-width="3"/>
      <path d="M32 18h4a4 4 0 0 1 0 8h-4" fill="none" stroke="#6b7280" stroke-width="3"/>
    </svg>
  SVG

  LOGOS = {
    "Blue Bottle" => BLUE_BOTTLE_LOGO,
    "E2E Test Coffee" => E2E_TEST_COFFEE_LOGO,
    "Live Test Coffee" => LIVE_TEST_COFFEE_LOGO,
  }.freeze

  DEFAULT_ACCENT = "#6b7280"

  ACCENTS = {
    "Blue Bottle" => "#2563eb",
    "E2E Test Coffee" => "#16a34a",
    "Live Test Coffee" => "#c2410c",
  }.freeze

  class << self
    def call(id:)
      place = CoffeePlace.find_by(id: id)

      return not_found_response(id) unless place

      ui_resource = McpUiServer.create_ui_resource(
        uri: "ui://coffee-place-card/#{place.id}",
        content: { type: :raw_html, htmlString: card_html(place) },
        encoding: :text,
      )

      MCP::Tool::Response.new([ui_resource])
    end

    private

    def not_found_response(id)
      MCP::Tool::Response.new([{ type: "text", text: "No coffee place found with id #{id}" }], error: true)
    end

    def rating_stars_html(place)
      (1..5).map do |n|
        glyph = place.rating && n <= place.rating ? "★" : "☆"
        "<button type=\"button\" onclick=\"sendAction('rate_coffee_place', {id: #{place.id}, rating: #{n}})\" style=\"all: unset; cursor: pointer; font-size: 1.5rem; line-height: 1;\">#{glyph}</button>"
      end.join
    end

    def favorite_drink_select_html(place)
      selected_value = place.favorite_drink ? "#{place.favorite_drink_type}-#{place.favorite_drink_id}" : ""

      options = ["<option value=\"\"#{selected_value.empty? ? " selected" : ""}>— none —</option>"]

      { "Coffee" => Coffee.order(:name), "Tea" => Tea.order(:name) }.each do |type, beverages|
        beverages.each do |beverage|
          value = "#{type}-#{beverage.id}"
          selected_attr = value == selected_value ? " selected" : ""
          options << "<option value=\"#{value}\"#{selected_attr}>#{ERB::Util.html_escape(beverage.name)}</option>"
        end
      end

      <<~HTML.strip
        <select onchange="var parts = this.value.split('-'); sendAction('set_favorite_drink', {id: #{place.id}, beverage_type: parts[0] || null, beverage_id: parts[1] ? Number(parts[1]) : null})">
          #{options.join("\n          ")}
        </select>
      HTML
    end

    def card_html(place)
      accent = ACCENTS.fetch(place.name, DEFAULT_ACCENT)
      logo_html = LOGOS.fetch(place.name, DEFAULT_LOGO)

      <<~HTML
        <!doctype html>
        <html>
          <head><meta charset="utf-8"></head>
          <body style="font-family: sans-serif; margin: 0; padding: 0;">
            <div style="border-top: 4px solid #{accent}; border-radius: 12px; box-shadow: 0 2px 8px rgba(0,0,0,0.12); padding: 1rem; margin: 0.5rem;">
              #{logo_html}
              <h2 style="margin: 0.5rem 0 0.25rem;">#{ERB::Util.html_escape(place.name)}</h2>
              <p style="margin: 0 0 0.5rem;">#{ERB::Util.html_escape(place.address)}</p>
              <p style="margin: 0 0 0.5rem;">#{rating_stars_html(place)}</p>
              <p style="margin: 0;">Favorite drink: #{favorite_drink_select_html(place)}</p>
            </div>
            <div id="toast" style="display:none; position: fixed; bottom: 1rem; right: 1rem; background: #111827; color: white; padding: 0.5rem 1rem; border-radius: 6px; font-size: 0.875rem;"></div>
            <script>
              function showToast(message) {
                var toast = document.getElementById('toast');
                toast.textContent = message;
                toast.style.display = 'block';
              }

              function sendAction(toolName, params) {
                showToast('Saving…');
                window.parent.postMessage({ type: 'tool', payload: { toolName: toolName, params: params } }, '*');
              }

              window.addEventListener('message', function (event) {
                if (!event.data || event.data.type !== 'tool-result') return;
                if (event.data.success) {
                  showToast('Saved via MCP ✓');
                } else {
                  showToast('Save failed: ' + (event.data.error || 'unknown error'));
                }
                setTimeout(function () {
                  var toast = document.getElementById('toast');
                  if (toast) toast.style.display = 'none';
                }, 2000);
              });
            </script>
          </body>
        </html>
      HTML
    end
  end
end
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bundle exec rspec spec/mcp_server/tools/coffee_place_card_tool_spec.rb`
Expected: PASS (8 examples, 0 failures).

- [ ] **Step 5: Run the full suite**

Run: `bundle exec rspec`
Expected: all examples pass except the one known pre-existing unrelated failure in `spec/features/adding_a_coffee_place_spec.rb`.

- [ ] **Step 6: Commit**

```bash
git add mcp_server/tools/coffee_place_card_tool.rb spec/mcp_server/tools/coffee_place_card_tool_spec.rb
git commit -m "Make the coffee place card interactive: clickable rating, favorite-drink select, accent styling"
```

---

### Task 6: Host page wiring, request-spec smoke check, and browser verification

**Files:**
- Modify: `app/views/coffee_places/show.html.erb`
- Modify: `spec/requests/coffee_places_spec.rb`

**Interfaces:**
- Consumes: `mcp_action_coffee_place_path` (Task 4), the card's `{type: "tool", payload: {toolName, params}}` message and its expected `{type: "tool-result", success, error?}` reply shape (Task 5).
- Produces: no new interface — this is the last task, wiring everything together end to end.

- [ ] **Step 1: Extend the existing request spec assertion**

In `spec/requests/coffee_places_spec.rb`, in the `"GET /coffee_places/:id"` describe block's first example ("renders the MCP-UI card in a sandboxed iframe when the MCP server responds"), add two assertions after the existing `expect(response.body).to include('sandbox="allow-scripts"')` line:

```ruby
      expect(response.body).to include('id="coffee-place-card"')
      expect(response.body).to include("mcp_action")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/requests/coffee_places_spec.rb`
Expected: FAIL — the iframe has no `id` attribute yet and the page has no reference to `mcp_action`.

- [ ] **Step 3: Rewrite the show view**

Replace the full contents of `app/views/coffee_places/show.html.erb` with:

```erb
<%= link_to "← Coffee places", coffee_places_path %>

<h2><%= @coffee_place.name %></h2>

<% if @mcp_unavailable %>
  <p class="notice">Live card unavailable — showing basic info.</p>
  <p><%= @coffee_place.address %></p>
  <% if @coffee_place.rating.present? %>
    <p class="place-rating"><%= "★" * @coffee_place.rating %><%= "☆" * (5 - @coffee_place.rating) %></p>
  <% end %>
  <% if @coffee_place.favorite_drink.present? %>
    <p class="place-favorite-drink">Favorite drink: <%= @coffee_place.favorite_drink.name %></p>
  <% end %>
<% else %>
  <%= content_tag :iframe, "", id: "coffee-place-card", srcdoc: @card_html, sandbox: "allow-scripts", style: "width: 100%; min-height: 260px; border: 0;" %>

  <script>
    (function () {
      var iframe = document.getElementById("coffee-place-card");
      if (!iframe) return;

      window.addEventListener("message", function (event) {
        if (event.source !== iframe.contentWindow) return;
        if (!event.data || event.data.type !== "tool") return;

        var toolName = event.data.payload.toolName;
        var params = event.data.payload.params;

        fetch("<%= mcp_action_coffee_place_path(@coffee_place) %>", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
            "Accept": "application/json"
          },
          body: JSON.stringify({ tool_name: toolName, params: params })
        })
          .then(function (response) {
            return response.json().then(function (data) {
              return { ok: response.ok, data: data };
            });
          })
          .then(function (result) {
            if (result.ok && result.data.html) {
              iframe.addEventListener("load", function replyOnce() {
                iframe.removeEventListener("load", replyOnce);
                iframe.contentWindow.postMessage({ type: "tool-result", success: true }, "*");
              });
              iframe.srcdoc = result.data.html;
            } else {
              iframe.contentWindow.postMessage({ type: "tool-result", success: false, error: (result.data && result.data.error) || "Unknown error" }, "*");
            }
          })
          .catch(function (err) {
            iframe.contentWindow.postMessage({ type: "tool-result", success: false, error: err.message }, "*");
          });
      });
    })();
  </script>
<% end %>
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bundle exec rspec spec/requests/coffee_places_spec.rb`
Expected: PASS (all examples).

- [ ] **Step 5: Run the full suite**

Run: `bundle exec rspec`
Expected: all examples pass except the one known pre-existing unrelated failure in `spec/features/adding_a_coffee_place_spec.rb`.

- [ ] **Step 6: Manually verify in a real browser**

With `bin/mcp_server` and `bin/rails server` both running (restart `bin/mcp_server` first if it was already running, since it loads tool code once at boot), visit a coffee place's show page and:
1. Click a rating star. Confirm the card briefly shows "Saving…", then the iframe reloads showing the new star count and "Saved via MCP ✓".
2. Change the favorite-drink select. Confirm the same "Saving…" → reload → "Saved via MCP ✓" sequence, and the select shows the newly chosen drink after reload.
3. Confirm via `bin/rails runner 'puts CoffeePlace.find(<id>).attributes'` (or reloading the page) that the DB record actually changed for both actions.

- [ ] **Step 7: Commit**

```bash
git add app/views/coffee_places/show.html.erb spec/requests/coffee_places_spec.rb
git commit -m "Wire the host page to relay card actions to the MCP server and swap in the refreshed card"
```

## Self-Review Notes

- **Spec coverage:** every behavior in the design doc maps to a task —
  `RateCoffeePlaceTool` (Task 1), `SetFavoriteDrinkTool` (Task 2),
  `Mcp::Client#call_action` + refactor (Task 3), the allowlisted endpoint
  (Task 4), the interactive/styled card (Task 5), the host page wiring
  (Task 6). Out-of-scope items from the design doc (no optimistic update,
  no message-id correlation, no auth) are simply not built anywhere here.
- **Type/name consistency checked:** `rate_coffee_place`/`set_favorite_drink`
  tool names (Tasks 1-2) match `CoffeePlacesController::ALLOWED_MCP_ACTIONS`
  (Task 4) and the card's `sendAction(...)` calls (Task 5) exactly.
  `Mcp::Client#call_action(tool_name, params)` (Task 3) matches the exact
  call site in `CoffeePlacesController#mcp_action` (Task 4).
  `mcp_action_coffee_place_path` (Task 4's route) matches Task 6's view.
  The card's outbound `{type: "tool", payload: {toolName, params}}` and
  inbound `{type: "tool-result", success, error}` message shapes (Task 5)
  match exactly what Task 6's host JS sends/expects.
