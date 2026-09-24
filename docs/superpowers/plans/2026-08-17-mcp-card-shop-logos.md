# MCP-UI Card Shop Logos Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an inline SVG "shop logo" to the MCP-UI coffee place card, with 3 hand-made logos for the 3 named coffee places currently in the dev DB and a default logo for everything else.

**Architecture:** Pure addition inside `CoffeePlaceCardTool#card_html` (`mcp_server/tools/coffee_place_card_tool.rb`) — a name-keyed `LOGOS` lookup with a `DEFAULT_LOGO` fallback, rendered above the place name in the same HTML string the tool already returns. No other file changes; the SVG is opaque HTML content to `Mcp::Client`, the controller, and the view.

**Tech Stack:** Ruby, rspec-rails (matches the rest of this branch).

## Global Constraints

- One file gets new behavior (`mcp_server/tools/coffee_place_card_tool.rb`); its spec is the only other file touched.
- Logo selection is exact-name lookup: `"Blue Bottle"` → blue mug, `"E2E Test Coffee"` → green to-go cup, `"Live Test Coffee"` → brown coffee bean, anything else → gray default mug outline.
- No new gem, tool, resource, DB column, or network request — the SVGs are inline string constants.
- Match existing spec conventions in this file: plain `CoffeePlace.create!`, `require "rails_helper"`, assertions via `.to include(...)` on the resource's HTML text.

---

### Task 1: Add shop logos to the coffee place card

**Files:**
- Modify: `mcp_server/tools/coffee_place_card_tool.rb`
- Modify: `spec/mcp_server/tools/coffee_place_card_tool_spec.rb`

**Interfaces:**
- Consumes: `CoffeePlace#name` (existing model attribute).
- Produces: no new public interface — `CoffeePlaceCardTool.call(id:)`'s returned HTML now additionally contains a `<svg>` logo block; every existing consumer (Task 6 of the original plan: `Mcp::Client`, `CoffeePlacesController#show`, `show.html.erb`) is unaffected since it treats the HTML as an opaque string.

- [ ] **Step 1: Write the failing spec assertions**

Add one assertion to the existing "returns an MCP-UI resource card for an existing coffee place" example (it creates a place named `"Blue Bottle"`), and add a new example for the default-logo case. Edit `spec/mcp_server/tools/coffee_place_card_tool_spec.rb` to read exactly:

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
    expect(resource_item[:resource][:text]).to include("Pour Over")
    expect(resource_item[:resource][:text]).to include('fill="#2563eb"')
  end

  it "renders a card without a favorite drink or rating" do
    place = CoffeePlace.create!(name: "Ritual", address: "456 Elm St")

    response = described_class.call(id: place.id)
    html = response.content.first[:resource][:text]

    expect(html).to include("Ritual")
    expect(html).to include("Not rated")
  end

  it "uses a specific logo for each of the 3 known shop names" do
    e2e = CoffeePlace.create!(name: "E2E Test Coffee", address: "123 Test St")
    live = CoffeePlace.create!(name: "Live Test Coffee", address: "456 Live St")

    e2e_html = described_class.call(id: e2e.id).content.first[:resource][:text]
    live_html = described_class.call(id: live.id).content.first[:resource][:text]

    expect(e2e_html).to include('fill="#16a34a"')
    expect(live_html).to include('fill="#c2410c"')
  end

  it "falls back to the default logo for an unrecognized shop name" do
    place = CoffeePlace.create!(name: "Ritual", address: "456 Elm St")

    html = described_class.call(id: place.id).content.first[:resource][:text]

    expect(html).to include('stroke="#6b7280"')
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
Expected: FAIL — the two new/extended examples fail because no `fill="#2563eb"`/`fill="#16a34a"`/`fill="#c2410c"`/`stroke="#6b7280"` text exists yet in the returned HTML (the other 3 examples still pass, unaffected).

- [ ] **Step 3: Add the logos to the tool**

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

    def card_html(place)
      rating_html = place.rating ? ("★" * place.rating) + ("☆" * (5 - place.rating)) : "Not rated"
      drink_html = place.favorite_drink ? "<p>Favorite drink: #{ERB::Util.html_escape(place.favorite_drink.name)}</p>" : ""
      logo_html = LOGOS.fetch(place.name, DEFAULT_LOGO)

      <<~HTML
        <!doctype html>
        <html>
          <head><meta charset="utf-8"></head>
          <body style="font-family: sans-serif; margin: 0; padding: 1rem;">
            #{logo_html}
            <h2>#{ERB::Util.html_escape(place.name)}</h2>
            <p>#{ERB::Util.html_escape(place.address)}</p>
            <p>#{rating_html}</p>
            #{drink_html}
          </body>
        </html>
      HTML
    end
  end
end
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bundle exec rspec spec/mcp_server/tools/coffee_place_card_tool_spec.rb`
Expected: PASS (5 examples, 0 failures).

- [ ] **Step 5: Run the full suite**

Run: `bundle exec rspec`
Expected: all examples pass except the one known pre-existing unrelated failure in `spec/features/adding_a_coffee_place_spec.rb` (out of scope, predates this branch).

- [ ] **Step 6: Manually verify**

With `bin/mcp_server` and `bin/rails server` both running, visit the show page for a coffee place named "Blue Bottle", "E2E Test Coffee", or "Live Test Coffee" in the dev DB and confirm its distinct logo renders above the name inside the card iframe; visit any other coffee place's show page and confirm the gray default logo renders instead.

- [ ] **Step 7: Commit**

```bash
git add mcp_server/tools/coffee_place_card_tool.rb spec/mcp_server/tools/coffee_place_card_tool_spec.rb
git commit -m "Add per-shop SVG logos to the MCP-UI coffee place card"
```

## Self-Review Notes

- **Spec coverage:** the design doc's only two behaviors (3 named logos, 1 default fallback) are both covered by Step 1's spec additions.
- **Placeholder scan:** none — all SVG markup, colors, and test assertions are concrete.
- **Type/name consistency:** `LOGOS`/`DEFAULT_LOGO` are defined and consumed within the same file/step; no cross-task interface to drift.
