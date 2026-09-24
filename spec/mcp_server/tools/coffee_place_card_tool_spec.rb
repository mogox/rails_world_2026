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

  it "constrains the card's own width so it cannot overflow the iframe" do
    place = CoffeePlace.create!(name: "Generic Cafe", address: "456 Elm St")

    html = described_class.call(id: place.id).content.first[:resource][:text]

    expect(html).to include("box-sizing: border-box")
    expect(html).to include("overflow-x: hidden")
    expect(html).to include("max-width: calc(100% - 1rem)")
  end

  it "uses a specific logo and accent color for each of the 5 known shop names" do
    ritual = CoffeePlace.create!(name: "Ritual Coffee Roasters", address: "123 Test St")
    saint_frank = CoffeePlace.create!(name: "Saint Frank Coffee", address: "456 Live St")
    sightglass = CoffeePlace.create!(name: "Sightglass Coffee", address: "789 Test St")
    philz = CoffeePlace.create!(name: "Philz Coffee", address: "321 Live St")

    ritual_html = described_class.call(id: ritual.id).content.first[:resource][:text]
    saint_frank_html = described_class.call(id: saint_frank.id).content.first[:resource][:text]
    sightglass_html = described_class.call(id: sightglass.id).content.first[:resource][:text]
    philz_html = described_class.call(id: philz.id).content.first[:resource][:text]

    expect(ritual_html).to include('fill="#16a34a"')
    expect(ritual_html).to include("--accent: #16a34a")
    expect(saint_frank_html).to include('fill="#c2410c"')
    expect(saint_frank_html).to include("--accent: #c2410c")
    expect(sightglass_html).to include('fill="#0d9488"')
    expect(sightglass_html).to include("--accent: #0d9488")
    expect(philz_html).to include('fill="#d97706"')
    expect(philz_html).to include("--accent: #d97706")
  end

  it "falls back to the default logo and accent color for an unrecognized shop name" do
    place = CoffeePlace.create!(name: "Generic Cafe", address: "456 Elm St")

    html = described_class.call(id: place.id).content.first[:resource][:text]

    expect(html).to include('stroke="#6b7280"')
    expect(html).to include("--accent: #6b7280")
  end

  it "styles rating buttons and the favorite-drink select with the card's accent-aware CSS classes" do
    place = CoffeePlace.create!(name: "Blue Bottle", address: "123 Main St")

    html = described_class.call(id: place.id).content.first[:resource][:text]

    expect(html.scan('class="mcp-star"').length).to eq(5)
    expect(html).to include('class="mcp-select"')
    expect(html).to include(".mcp-star:hover")
    expect(html).to include(".mcp-select:focus")
    expect(html).to include("--accent-rgb: 37, 99, 235")
  end

  it "shows a tool-specific confirmation toast label for each action" do
    place = CoffeePlace.create!(name: "Generic Cafe", address: "456 Elm St")

    html = described_class.call(id: place.id).content.first[:resource][:text]

    expect(html).to include('"rate_coffee_place":"Rating"')
    expect(html).to include('"set_favorite_drink":"Favorite drink"')
    expect(html).to include("label + ' updated via MCP")
  end

  it "reads the tool name and params from the tool-result message itself, not from script-local state" do
    place = CoffeePlace.create!(name: "Generic Cafe", address: "456 Elm St")

    html = described_class.call(id: place.id).content.first[:resource][:text]

    # The host does a full iframe.srcdoc replacement between sendAction and the
    # tool-result reply, so any script-local state set by sendAction (lastToolName,
    # lastParams) is gone by the time the reply arrives in the freshly-loaded card.
    # The reply must be self-describing instead.
    expect(html).to include("handleActionSuccess(event.data.toolName, event.data.params)")
    expect(html).to include("function handleActionSuccess(toolName, params)")
    expect(html).to include("TOOL_LABELS[toolName]")
  end

  it "renders 5 clickable rating buttons reflecting the current rating" do
    place = CoffeePlace.create!(name: "Generic Cafe", address: "456 Elm St", rating: 3)

    html = described_class.call(id: place.id).content.first[:resource][:text]

    expect(html.scan("sendAction('rate_coffee_place'").length).to eq(5)
    # Scoped to the clickable rating buttons themselves, not the always-filled
    # 5 gold stars inside the (hidden-by-default) celebration overlay.
    expect(html.scan(">★</button>").length).to eq(3)
    expect(html.scan(">☆</button>").length).to eq(2)
  end

  it "renders all stars empty when there is no rating yet" do
    place = CoffeePlace.create!(name: "Generic Cafe", address: "456 Elm St")

    html = described_class.call(id: place.id).content.first[:resource][:text]

    # Scoped to the clickable rating buttons; the celebration overlay's 5 gold
    # stars are always rendered (filled), just hidden until a 5-star rating fires.
    expect(html.scan(">☆</button>").length).to eq(5)
    expect(html).not_to include(">★</button>")
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
    place = CoffeePlace.create!(name: "Generic Cafe", address: "456 Elm St")

    html = described_class.call(id: place.id).content.first[:resource][:text]

    expect(html).to include('<option value="" selected>— none —</option>')
  end

  it "includes a night-sky celebration overlay that triggers only on a confirmed 5-star rating" do
    place = CoffeePlace.create!(name: "Generic Cafe", address: "456 Elm St")

    html = described_class.call(id: place.id).content.first[:resource][:text]

    expect(html).to include('id="celebration"')
    expect(html).to include("celebration-star")
    expect(html).to include("celebration-comet")
    expect(html).to include("@keyframes twinkle")
    expect(html).to include("@keyframes comet-fly")
    expect(html).to include("toolName === 'rate_coffee_place' && params && params.rating === 5")
  end

  it "shows 5 large, blinking gold stars inside the celebration overlay" do
    place = CoffeePlace.create!(name: "Generic Cafe", address: "456 Elm St")

    html = described_class.call(id: place.id).content.first[:resource][:text]

    expect(html.scan('class="celebration-rating-star"').length).to eq(5)
    expect(html).to include("@keyframes celebration-star-blink")
    expect(html).to include(".celebration-rating-star")
  end

  it "keeps the shop name and icon visible, in white, inside the celebration overlay" do
    place = CoffeePlace.create!(name: "Blue Bottle", address: "123 Main St")

    html = described_class.call(id: place.id).content.first[:resource][:text]

    # Rendered once in the main card, and again inside the celebration overlay
    # (the Blue Bottle logo itself uses fill="#2563eb" twice, so 2x that = 4).
    expect(html.scan("Blue Bottle").length).to eq(2)
    expect(html.scan('fill="#2563eb"').length).to eq(4)
    expect(html).to include("celebration-logo")
    expect(html).to include("celebration-name")
    expect(html).to include("filter: brightness(0) invert(1)")
  end

  it "returns an error response when the coffee place does not exist" do
    response = described_class.call(id: -1)

    expect(response.error?).to be(true)
    expect(response.content.first[:text]).to include("No coffee place found")
  end

  it "links the tool to its MCP Apps UI template via _meta.ui.resourceUri" do
    expect(described_class::TEMPLATE_URI).to eq("ui://coffee-place-card/template")
    expect(described_class.to_h[:_meta]).to eq(ui: { resourceUri: "ui://coffee-place-card/template" })
  end

  it "emits both the Rails message shape and a real JSON-RPC tools/call per action" do
    place = CoffeePlace.create!(name: "Generic Cafe", address: "456 Elm St")

    html = described_class.call(id: place.id).content.first[:resource][:text]

    # Rails path, unchanged.
    expect(html).to include("window.parent.postMessage({ type: 'tool', payload:")
    # MCP Apps path.
    expect(html).to include("window.mcpApps.callTool(toolName, params)")
  end

  it "embeds the MCP Apps bridge and a connect() call naming itself" do
    place = CoffeePlace.create!(name: "Generic Cafe", address: "456 Elm St")

    html = described_class.call(id: place.id).content.first[:resource][:text]

    expect(html).to include("window.mcpApps = {")
    expect(html).to include("'ui/initialize'")
    # appInfo is a required ui/initialize param and the bridge stays free of any
    # app vocabulary, so the card supplies its own.
    expect(html).to include(%(window.mcpApps.connect({"name":"coffee-place-card","version":"1.0.0"})))
  end

  it "emits a console.error diagnostic rather than swallowing a failed handshake" do
    place = CoffeePlace.create!(name: "Generic Cafe", address: "456 Elm St")

    html = described_class.call(id: place.id).content.first[:resource][:text]

    expected = "window.mcpApps.connect(#{described_class::APP_INFO.to_json})" \
      ".catch(function (error) { console.error('MCP Apps handshake failed:', error); });"

    expect(html).to include(expected)
  end

  it "skips the tools/call entirely once the handshake has failed, instead of toasting a false failure" do
    place = CoffeePlace.create!(name: "Generic Cafe", address: "456 Elm St")

    html = described_class.call(id: place.id).content.first[:resource][:text]

    # Under Rails this card runs in a sandboxed srcdoc iframe, so `available`
    # (window.parent !== window) is always true while Rails never answers
    # ui/initialize. Gating the MCP Apps branch on `available` alone meant that
    # after the handshake's bounded wait every click rejected and flashed
    # "Save failed: MCP Apps handshake timed out after 10000ms" for the whole
    # Rails round trip — over a save that had in fact succeeded.
    expect(html).to include(
      "if (window.mcpApps && window.mcpApps.available && !window.mcpApps.handshakeFailed()) {",
    )
    # The doomed call is not issued at all; the toast is not merely suppressed.
    expect(html.scan("window.mcpApps.callTool(toolName, params)").length).to eq(1)
  end

  it "spells the ui:// prefix once and derives every card URI from it" do
    place = CoffeePlace.create!(name: "Generic Cafe", address: "456 Elm St")

    expect(described_class::CARD_URI_PREFIX).to eq("ui://coffee-place-card/")
    expect(described_class::TEMPLATE_URI).to eq("#{described_class::CARD_URI_PREFIX}template")
    expect(described_class.call(id: place.id).content.first[:resource][:uri])
      .to eq("#{described_class::CARD_URI_PREFIX}#{place.id}")
  end

  it "refreshes itself in place by re-reading its own ui:// resource after an action" do
    place = CoffeePlace.create!(name: "Generic Cafe", address: "456 Elm St")

    html = described_class.call(id: place.id).content.first[:resource][:text]

    expect(html).to include("var PLACE_ID = #{place.id};")
    expect(html).to include("window.mcpApps.readResource('ui://coffee-place-card/' + PLACE_ID)")
    expect(html).to include("function applyCard(")
    # In-place DOM update, NOT an iframe reload.
    expect(html).to include("DOMParser")
  end

  it "routes both hosts' success paths through one toast/celebration function" do
    place = CoffeePlace.create!(name: "Generic Cafe", address: "456 Elm St")

    html = described_class.call(id: place.id).content.first[:resource][:text]

    # Called once from the MCP Apps promise chain and once from the Rails
    # message listener, so the two hosts cannot drift apart.
    expect(html.scan("handleActionSuccess(").length).to eq(3) # definition + 2 call sites
    expect(html).to include("handleActionSuccess(toolName, params);")
  end

  describe ".template_html" do
    it "emits a connect() call naming itself, then a tool-input handler that reads the per-place card" do
      html = described_class.template_html

      expect(html).to include("window.mcpApps.connect(#{described_class::APP_INFO.to_json})")
      expect(html).to include("window.mcpApps.onToolInput(")
      expect(html).to include("'#{described_class::CARD_URI_PREFIX}' + args.id")
    end

    it "installs the whole fetched card document, scripts included" do
      html = described_class.template_html

      # The fetched card carries its own <script>; innerHTML would not run it,
      # so the shell replaces the document wholesale via document.write.
      expect(html).to include("document.open()")
      expect(html).to include("document.write(")
      expect(html).to include("document.close()")
    end

    it "shows a placeholder before the card arrives" do
      html = described_class.template_html

      expect(html).to include("Loading coffee place…")
    end

    it "embeds the MCP Apps bridge" do
      expect(described_class.template_html).to include("window.mcpApps = {")
    end

    it "gives up on a silent handshake or a silent host with a bounded, logged timeout" do
      html = described_class.template_html

      expect(html).to include("setTimeout(function () {")
      expect(html).to include("if (cardInstalled || errorShown) return;")
      expect(html).to include("console.error('MCP Apps shell: ' + message)")
      expect(html).to include(", #{McpApps::Bridge::HANDSHAKE_TIMEOUT_MS});")
    end

    it "cancels the loading timeout once a card is installed or an error is already shown" do
      html = described_class.template_html

      expect(html).to include("clearTimeout(loadingTimer);")
      expect(html.scan("clearTimeout(loadingTimer);").length).to eq(2) # installCard + showShellError
    end

    it "treats a non-numeric id (e.g. the template resource's own 'template' id) as missing" do
      html = described_class.template_html

      expect(html).to include("!/^\\d+$/.test(String(args.id))")
    end
  end
end
