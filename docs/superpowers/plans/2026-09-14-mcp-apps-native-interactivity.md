# MCP Apps Native Interactivity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the coffee place card genuinely interactive inside MCP Apps-compliant hosts (Claude Desktop) — clicking a star or picking a drink calls the real tool over the live MCP session and updates the card in place — without changing anything about how the existing Rails demo works.

**Architecture:** The server declares the MCP Apps extension (`io.modelcontextprotocol/ui`), links `get_coffee_place_card` to a static UI template resource via `_meta.ui.resourceUri`, and registers a per-place resource template `ui://coffee-place-card/{id}` serving the *existing* server-rendered card HTML at mimeType `text/html;profile=mcp-app`. The template resource is a thin shell that completes the `ui/initialize` handshake, learns the place id from `ui/notifications/tool-input`, reads the per-place resource, and injects it. Card actions dual-emit: the existing Rails-shaped `postMessage` **and** a real JSON-RPC `tools/call`, so one server-rendered card works in both environments.

**Tech Stack:** Ruby 3.4.1, Rails 8.1, `mcp` gem 1.2.0 (ships `MCP::Apps`), `mcp_ui_server` 0.1.0 (Rails path only), RSpec.

**Spec:** `docs/superpowers/specs/2026-09-14-mcp-apps-native-interactivity-design.md`

---

## Spec Corrections (read before Task 1)

Three claims in the spec were checked against the installed gem and the
ratified MCP Apps specification and are **wrong**. This plan implements the
corrected versions. The spec's *intent* is preserved everywhere.

**1. There IS a Ruby MCP Apps SDK — it is already installed.**
The spec says "There is no Ruby MCP Apps SDK to reach for instead" and plans a
hand-rolled, gem-extraction-ready `McpApps` module. But `mcp` 1.2.0 ships
`MCP::Apps` (`lib/mcp/apps.rb`), which provides exactly the helpers the spec
proposed to write:

- `MCP::Apps.tool_meta(resource_uri:, visibility: nil, meta: nil, legacy: false)` → `{ ui: { resourceUri: ... } }`
- `MCP::Apps.ui_resource(uri:, name:, mime_type: RESOURCE_MIME_TYPE, **rest)` → an `MCP::Resource`, validating the `ui://` scheme
- `MCP::Apps.capability(mime_types: [RESOURCE_MIME_TYPE])` → `{ "io.modelcontextprotocol/ui" => { mimeTypes: [...] } }`
- `MCP::Apps.client_supports?(client_capabilities, mime_type:)`
- `MCP::Apps::RESOURCE_MIME_TYPE == "text/html;profile=mcp-app"`, `MCP::Apps::EXTENSION_ID == "io.modelcontextprotocol/ui"`

**Use `MCP::Apps` directly. Do not hand-roll a server-side `McpApps` module.**
The spec's "gem-extraction-ready" instinct still applies to the one piece the
gem does *not* cover — the browser-side JSON-RPC-over-postMessage bridge — which
Task 2 builds as a self-contained `McpApps::Bridge` module with no
coffee-place-specific types.

**2. The spec omits capability negotiation, which is mandatory.**
MCP Apps is negotiated per SEP-2133 through `capabilities.extensions`. A server
that does not declare the extension is not treated as an Apps server no matter
what `_meta` its tools carry. Task 4 adds `support_extensions(MCP::Apps.capability)`
plus `support_tools` / `support_resources`.

**3. `_meta.ui.resourceUri` CANNOT be templated — `ui://coffee-place-card/{id}` is invalid there.**
The spec's server section proposes `_meta: { ui: { resourceUri: "ui://coffee-place-card/{id}" } }`.
The ratified spec requires a concrete, pre-declared `ui://` URI; there is no RFC
6570 expansion of `resourceUri`, and per-call data is explicitly designed to flow
through notifications instead ("Separate template (static) from data (dynamic)").
A tool's `_meta` is static at definition time and cannot know the place id anyway.

Corrected design, which still satisfies every goal the spec states (one
card-rendering implementation, no JS-side rendering, no iframe reload):

- The tool links to a **static** template resource `ui://coffee-place-card/template`.
- That template is a thin shell: it handshakes, receives the tool's arguments via
  `ui/notifications/tool-input` (`{ arguments: { id: 3 } }`), then reads
  `ui://coffee-place-card/3` and injects the server-rendered card.
- The per-place **resource template** `ui://coffee-place-card/{id}` (which the
  `mcp` gem *does* support via `define_resource_template`) is still registered
  exactly as the spec asks, and is what the shell and the post-action refresh read.

**4. The spec omits the mandatory `ui/initialize` handshake.**
The spec's card-side section jumps straight to posting `tools/call`. The real
bridge lifecycle is: View sends `ui/initialize` → Host replies with
`McpUiInitializeResult` → View sends `ui/notifications/initialized` → only then
does the Host send `ui/notifications/tool-input` and service View-initiated
calls. Task 2 implements this handshake. This is very likely a second reason
nothing happens in Claude Desktop today, independent of the linkage/mimeType gaps.

Everything else in the spec — additive-only changes, Rails untouched, no
`@modelcontextprotocol/ext-apps` bundling, no gem packaging, no concurrent-action
handling, no changes to `rate_coffee_place`/`set_favorite_drink` definitions —
stands as written.

## Global Constraints

- **Rails path must not change.** `app/views/coffee_places/show.html.erb` and
  `app/services/mcp/client.rb` are untouched. `CoffeePlaceCardTool.call(id:)`'s
  *response* keeps returning the `mcp_ui_server` embedded resource at mimeType
  `text/html` under uri `ui://coffee-place-card/<id>`.
- **Baseline is 70 green examples** (`bundle exec rspec` → `70 examples, 0 failures`).
  Every task ends with the full suite green and the count only going up.
- **MIME type for the Apps path is exactly** `text/html;profile=mcp-app`
  (use `MCP::Apps::RESOURCE_MIME_TYPE`, never a string literal).
- **Extension id is exactly** `io.modelcontextprotocol/ui` (use `MCP::Apps::EXTENSION_ID`).
- **Static template URI is exactly** `ui://coffee-place-card/template`.
- **Per-place URI template is exactly** `ui://coffee-place-card/{id}`.
- **No new gems.** No JS build step. No npm packages vendored.
- **Single in-flight action only** — a plain incrementing integer id and a pending
  map are sufficient; do not build a request queue with retry/timeout semantics.
- Run tests with `bundle exec rspec`. Ruby files use `# frozen_string_literal: true`.

---

## File Structure

| File | Responsibility |
|---|---|
| `mcp_server/mcp_apps/bridge.rb` (create) | `McpApps::Bridge.script` — generic browser-side JSON-RPC-over-postMessage bridge JS. No coffee-place types. Gem-extraction-ready. |
| `mcp_server/tools/coffee_place_card_tool.rb` (modify) | Split `card_html` into `card_styles_css` / `card_body_html` / `card_script_js`; add `tool_meta`; add `shell_html`; dual-emit in the card script. |
| `mcp_server/server.rb` (modify) | Declare Apps capability; register the static template resource and the `{id}` resource template. |
| `spec/mcp_server/mcp_apps/bridge_spec.rb` (create) | Bridge JS contents. |
| `spec/mcp_server/tools/coffee_place_card_tool_spec.rb` (modify) | `_meta`, shell, dual-emit assertions; all existing examples unchanged. |
| `spec/mcp_server/server_spec.rb` (modify) | Capabilities, resource, resource-template registration and `resources/read` routing. |

---

### Task 1: Split `card_html` into composable parts

Pure refactor. `card_html(place)` must produce a byte-identical string
afterwards, so all 70 existing examples pass untouched. Later tasks need the
script and the body separately (the shell reuses the script; the shell injects
the body).

**Files:**
- Modify: `mcp_server/tools/coffee_place_card_tool.rb:141-373`
- Test: `spec/mcp_server/tools/coffee_place_card_tool_spec.rb` (no changes — existing examples ARE the test)

**Interfaces:**
- Consumes: nothing
- Produces (all `private` class methods on `CoffeePlaceCardTool`):
  - `card_styles_css(place)` → `String` — the CSS currently inside `<style>`, indented as today
  - `card_body_html(place)` → `String` — the markup currently inside `<body>`, excluding `<script>`
  - `card_script_js` → `String` — the JS currently inside `<script>`
  - `card_html(place)` → `String` — full document, unchanged output

- [ ] **Step 1: Run the existing card spec to confirm the baseline is green**

Run: `bundle exec rspec spec/mcp_server/tools/coffee_place_card_tool_spec.rb`
Expected: PASS, 15 examples, 0 failures.

- [ ] **Step 2: Extract the three parts**

In `mcp_server/tools/coffee_place_card_tool.rb`, replace the body of the
`card_html` method (currently lines 141-373) with four methods. Move the
existing content verbatim — do not retype or reformat it, and keep the exact
leading whitespace so the heredoc output is unchanged.

```ruby
    def card_styles_css(place)
      accent = ACCENTS.fetch(place.name, DEFAULT_ACCENT)
      accent_rgb_value = accent_rgb(accent)

      <<~CSS.chomp
        * { box-sizing: border-box; }

        :root {
          --accent: #{accent};
          --accent-rgb: #{accent_rgb_value};
        }
      CSS
    end
```

The `CSS` heredoc above shows only its first two rules. It must contain **every
rule currently inside the `<style>` block — the whole of lines 152-292 of
`mcp_server/tools/coffee_place_card_tool.rb`, moved verbatim** (`* { box-sizing }`,
`:root`, `.mcp-star`, `.mcp-star:hover`, `.mcp-select`, `.mcp-select:hover`,
`.mcp-select:focus`, `.celebration`, `.celebration-star`, `@keyframes twinkle`,
`.celebration-comet`, `.celebration-comet::before`, `@keyframes comet-fly`,
`.celebration-header`, `.celebration-rating`, `.celebration-rating-star`,
`@keyframes celebration-star-blink`, `.celebration-logo`, `.celebration-name`),
dedented by 6 spaces so `<<~` strips cleanly. Cut and paste it; do not retype it.

```ruby

    def card_body_html(place)
      logo_html = LOGOS.fetch(place.name, DEFAULT_LOGO)

      <<~HTML.chomp
        <div style="border-top: 4px solid var(--accent); border-radius: 12px; box-shadow: 0 2px 8px rgba(0,0,0,0.12); padding: 1.25rem; margin: 0.5rem; max-width: calc(100% - 1rem);">
          #{logo_html}
          <h2 style="margin: 0.75rem 0 0.25rem;">#{ERB::Util.html_escape(place.name)}</h2>
          <p style="margin: 0 0 0.5rem;">#{ERB::Util.html_escape(place.address)}</p>
          <p style="margin: 0 0 0.75rem;">#{rating_stars_html(place)}</p>
          <p style="margin: 0;">Favorite drink: #{favorite_drink_select_html(place)}</p>
        </div>
        <div id="toast" style="display:none; position: fixed; bottom: 1rem; right: 1rem; background: #111827; color: white; padding: 0.5rem 1rem; border-radius: 6px; font-size: 0.875rem;"></div>
        <div id="celebration" class="celebration">
          <div class="celebration-header">
            <div class="celebration-logo">#{logo_html}</div>
            <div class="celebration-name">#{ERB::Util.html_escape(place.name)}</div>
          </div>
          <div class="celebration-rating">#{celebration_rating_html}</div>
          <div class="celebration-stars"></div>
          <div class="celebration-comet"></div>
        </div>
      HTML
    end

    def card_script_js
      # Lines 313-368 of the current file, moved verbatim: the leading NOTE
      # comment, `var TOOL_LABELS = #{TOOL_LABELS.to_json};`, showToast,
      # sendAction, showCelebration, the celebration click listener, and the
      # `message` listener. Cut and paste; Task 5 rewrites this method anyway,
      # so do not improve it here.
      <<~JS.chomp
        // NOTE: the host does a full iframe.srcdoc replacement between sendAction
        // ... (lines 313-368, dedented by 6 spaces)
      JS
    end

    def card_html(place)
      <<~HTML
        <!doctype html>
        <html>
          <head>
            <meta charset="utf-8">
            <style>
        #{card_styles_css(place).gsub(/^/, "      ")}
            </style>
          </head>
          <body style="font-family: sans-serif; margin: 0; padding: 0; max-width: 100vw; overflow-x: hidden;">
        #{card_body_html(place).gsub(/^/, "    ")}
            <script>
        #{card_script_js.gsub(/^/, "      ")}
            </script>
          </body>
        </html>
      HTML
    end
```

Note on indentation: the existing tests assert on *substrings*
(`include("box-sizing: border-box")`, `include("--accent: #2563eb")`), not on
exact whitespace, so the `gsub` re-indentation above only has to keep the
document readable and keep every asserted substring intact. If a substring test
fails, fix the indentation rather than the test.

- [ ] **Step 3: Run the card spec — it must still pass unchanged**

Run: `bundle exec rspec spec/mcp_server/tools/coffee_place_card_tool_spec.rb`
Expected: PASS, 15 examples, 0 failures. Any failure means the refactor changed
output; fix the extraction, never the assertions.

- [ ] **Step 4: Run the full suite**

Run: `bundle exec rspec`
Expected: PASS, 70 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add mcp_server/tools/coffee_place_card_tool.rb
git commit -m "Split card_html into styles/body/script parts

Pure refactor, identical output. The MCP Apps shell needs the card's
script and body separately.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `McpApps::Bridge` — the browser-side JSON-RPC bridge

The one generic piece `MCP::Apps` does not ship: the View side of the
postMessage bridge. Self-contained, no coffee-place types, so extracting it to a
gem later is a directory move.

**Files:**
- Create: `mcp_server/mcp_apps/bridge.rb`
- Test: `spec/mcp_server/mcp_apps/bridge_spec.rb`

**Interfaces:**
- Consumes: nothing
- Produces: `McpApps::Bridge.script` → `String` of JavaScript defining `window.mcpApps` with:
  - `mcpApps.connect()` → Promise, completes the `ui/initialize` → `ui/notifications/initialized` handshake
  - `mcpApps.request(method, params)` → Promise resolving the JSON-RPC `result`, rejecting on `error`; queues until the handshake completes
  - `mcpApps.callTool(name, args)` → `request("tools/call", { name: name, arguments: args })`
  - `mcpApps.readResource(uri)` → `request("resources/read", { uri: uri })`
  - `mcpApps.onToolInput(fn)` → registers a callback invoked with the `ui/notifications/tool-input` `params.arguments` object
  - `mcpApps.available` → `true` when running inside a frame (`window.parent !== window`)

- [ ] **Step 1: Write the failing test**

Create `spec/mcp_server/mcp_apps/bridge_spec.rb`:

```ruby
require "rails_helper"
require_relative "../../../mcp_server/mcp_apps/bridge"

RSpec.describe McpApps::Bridge do
  let(:script) { described_class.script }

  it "performs the MCP Apps initialize handshake before anything else" do
    expect(script).to include("'ui/initialize'")
    expect(script).to include("'ui/notifications/initialized'")
    expect(script).to include("appCapabilities")
  end

  it "exposes tools/call and resources/read helpers over the bridge" do
    expect(script).to include("'tools/call'")
    expect(script).to include("'resources/read'")
    expect(script).to include("callTool")
    expect(script).to include("readResource")
  end

  it "correlates replies by JSON-RPC id and ignores unrelated messages" do
    expect(script).to include("jsonrpc")
    expect(script).to include("pending[")
    expect(script).to include("nextId")
  end

  it "delivers the host's tool-input notification to a registered callback" do
    expect(script).to include("'ui/notifications/tool-input'")
    expect(script).to include("onToolInput")
  end

  it "queues requests made before the handshake completes" do
    expect(script).to include("queue")
    expect(script).to include("ready")
  end

  it "is free of coffee-place-specific vocabulary so it can be extracted as-is" do
    expect(script).not_to match(/coffee|rating|drink|celebration/i)
  end
end
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bundle exec rspec spec/mcp_server/mcp_apps/bridge_spec.rb`
Expected: FAIL — `cannot load such file -- .../mcp_server/mcp_apps/bridge`

- [ ] **Step 3: Write the implementation**

Create `mcp_server/mcp_apps/bridge.rb`:

```ruby
# frozen_string_literal: true

# Browser-side half of the MCP Apps (SEP-1865) postMessage bridge.
#
# `MCP::Apps` in the `mcp` gem covers the SERVER half — capability declaration,
# `_meta.ui.resourceUri`, the `ui://` resource MIME type. The View half is the
# host's own client runtime in JS/TS (`@modelcontextprotocol/ext-apps`), which a
# Ruby server has no way to vendor without a JS build step. This emits the small
# subset a server-rendered view actually needs, hand-written.
#
# Deliberately free of any application vocabulary: it is a candidate for
# extraction into a gem once there is more than one consumer.
module McpApps
  module Bridge
    PROTOCOL_VERSION = "2026-01-26"

    module_function

    def script
      <<~JS.chomp
        (function () {
          var nextId = 1;
          var pending = {};
          var queue = [];
          var ready = false;
          var toolInputHandlers = [];
          var available = window.parent !== window;

          function post(message) {
            window.parent.postMessage(message, '*');
          }

          function request(method, params) {
            return new Promise(function (resolve, reject) {
              var id = nextId++;
              var send = function () {
                pending[id] = { resolve: resolve, reject: reject };
                post({ jsonrpc: '2.0', id: id, method: method, params: params });
              };
              if (ready || method === 'ui/initialize') { send(); } else { queue.push(send); }
            });
          }

          function notify(method, params) {
            post({ jsonrpc: '2.0', method: method, params: params || {} });
          }

          window.addEventListener('message', function (event) {
            var data = event.data;
            if (!data || data.jsonrpc !== '2.0') return;

            if (data.method === 'ui/notifications/tool-input') {
              var args = (data.params && data.params.arguments) || {};
              toolInputHandlers.forEach(function (fn) { fn(args); });
              return;
            }

            if (data.id === undefined || data.id === null) return;
            var entry = pending[data.id];
            if (!entry) return;
            delete pending[data.id];

            if (data.error) {
              entry.reject(new Error(data.error.message || 'MCP Apps request failed'));
            } else {
              entry.resolve(data.result);
            }
          });

          window.mcpApps = {
            available: available,

            connect: function () {
              if (!available) return Promise.reject(new Error('not in a frame'));
              return request('ui/initialize', {
                appCapabilities: { availableDisplayModes: ['inline', 'fullscreen'] }
              }).then(function (result) {
                notify('ui/notifications/initialized');
                ready = true;
                queue.splice(0).forEach(function (send) { send(); });
                return result;
              });
            },

            request: request,

            callTool: function (name, args) {
              return request('tools/call', { name: name, arguments: args });
            },

            readResource: function (uri) {
              return request('resources/read', { uri: uri });
            },

            onToolInput: function (fn) {
              toolInputHandlers.push(fn);
            }
          };
        })();
      JS
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bundle exec rspec spec/mcp_server/mcp_apps/bridge_spec.rb`
Expected: PASS, 6 examples, 0 failures.

- [ ] **Step 5: Run the full suite**

Run: `bundle exec rspec`
Expected: PASS, 76 examples, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add mcp_server/mcp_apps/bridge.rb spec/mcp_server/mcp_apps/bridge_spec.rb
git commit -m "Add McpApps::Bridge, the View half of the MCP Apps postMessage bridge

MCP::Apps in the mcp gem covers the server half; the View half only ships
as a Node package. Hand-rolled here, application-agnostic.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Link the tool to its UI template via `_meta.ui.resourceUri`

**Files:**
- Modify: `mcp_server/tools/coffee_place_card_tool.rb:3-10` (class body, after `input_schema`)
- Test: `spec/mcp_server/tools/coffee_place_card_tool_spec.rb`

**Interfaces:**
- Consumes: `MCP::Apps.tool_meta` (gem), `MCP::Apps::RESOURCE_MIME_TYPE` (gem)
- Produces: `CoffeePlaceCardTool::TEMPLATE_URI` → `"ui://coffee-place-card/template"`;
  `CoffeePlaceCardTool.to_h[:_meta]` → `{ ui: { resourceUri: TEMPLATE_URI } }`

- [ ] **Step 1: Write the failing test**

Append to `spec/mcp_server/tools/coffee_place_card_tool_spec.rb`, inside the
existing `RSpec.describe CoffeePlaceCardTool do` block:

```ruby
  it "links the tool to its MCP Apps UI template via _meta.ui.resourceUri" do
    expect(described_class::TEMPLATE_URI).to eq("ui://coffee-place-card/template")
    expect(described_class.to_h[:_meta]).to eq(ui: { resourceUri: "ui://coffee-place-card/template" })
  end
```

One example, not two. The Rails-path regression guard this task might otherwise
add — "`call` still returns the embedded resource at mimeType `text/html`" — is
already asserted by the first pre-existing example in this file, on the same
fixture. Restating it here would add no coverage.

- [ ] **Step 2: Run it to make sure it fails**

Run: `bundle exec rspec spec/mcp_server/tools/coffee_place_card_tool_spec.rb -e "links the tool"`
Expected: FAIL — `uninitialized constant CoffeePlaceCardTool::TEMPLATE_URI`

- [ ] **Step 3: Write the implementation**

In `mcp_server/tools/coffee_place_card_tool.rb`, immediately after the
`input_schema(...)` call (currently ending line 10), add:

```ruby
  # The static MCP Apps UI template this tool renders through. Per the ratified
  # spec the linked `resourceUri` MUST be a concrete, pre-declared `ui://` URI —
  # it is NOT an RFC 6570 template, and per-call data (here, which place) flows
  # through `ui/notifications/tool-input` instead. The per-place card itself is
  # served by the `ui://coffee-place-card/{id}` resource template, which the
  # shell reads once it knows the id.
  TEMPLATE_URI = "ui://coffee-place-card/template"

  meta MCP::Apps.tool_meta(resource_uri: TEMPLATE_URI)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec rspec spec/mcp_server/tools/coffee_place_card_tool_spec.rb`
Expected: PASS, 16 examples, 0 failures.

- [ ] **Step 5: Run the full suite**

Run: `bundle exec rspec`
Expected: PASS, 77 examples, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add mcp_server/tools/coffee_place_card_tool.rb spec/mcp_server/tools/coffee_place_card_tool_spec.rb
git commit -m "Link get_coffee_place_card to its MCP Apps UI template

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Declare the Apps capability and register both resources

Adds the shell resource (`ui://coffee-place-card/template`) and the per-place
resource template (`ui://coffee-place-card/{id}`). The shell's HTML body is a
placeholder in this task; Task 6 fills it in. That keeps this task about
*registration and routing*, which is what a reviewer gates here.

**Files:**
- Modify: `mcp_server/server.rb`
- Modify: `mcp_server/tools/coffee_place_card_tool.rb` (expose two public entry points)
- Test: `spec/mcp_server/server_spec.rb`

**Interfaces:**
- Consumes: `CoffeePlaceCardTool::TEMPLATE_URI` (Task 3); `McpApps::Bridge.script` (Task 2); `card_html` (Task 1)
- Produces:
  - `CoffeePlaceCardTool.template_html` → `String` (public) — the shell document
  - `CoffeePlaceCardTool.card_html_for(id)` → `String` or `nil` (public) — full card HTML for a place id, `nil` when not found
  - `McpServer.build` returns a server whose `capabilities` includes `extensions`, whose `resources` includes the template resource, and whose `resource_templates` includes `ui://coffee-place-card/{id}`

- [ ] **Step 1: Write the failing test**

Replace the contents of `spec/mcp_server/server_spec.rb` with:

```ruby
require "rails_helper"
require_relative "../../mcp_server/server"

RSpec.describe "McpServer" do
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

    contents = server.send(:read_resource, { uri: CoffeePlaceCardTool::TEMPLATE_URI })

    expect(contents.first[:uri]).to eq(CoffeePlaceCardTool::TEMPLATE_URI)
    expect(contents.first[:mimeType]).to eq("text/html;profile=mcp-app")
    expect(contents.first[:text]).to include("<!doctype html>")
  end

  it "serves the per-place card through the ui://coffee-place-card/{id} resource template" do
    place = CoffeePlace.create!(name: "Blue Bottle", address: "123 Main St", rating: 4)
    server = McpServer.build

    contents = server.send(:read_resource, { uri: "ui://coffee-place-card/#{place.id}" })

    expect(contents.first[:uri]).to eq("ui://coffee-place-card/#{place.id}")
    expect(contents.first[:mimeType]).to eq("text/html;profile=mcp-app")
    expect(contents.first[:text]).to include("Blue Bottle")
    expect(contents.first[:text]).to include("123 Main St")
  end

  it "serves the same HTML through the resource template as the tool embeds" do
    place = CoffeePlace.create!(name: "Philz Coffee", address: "456 Elm St")
    server = McpServer.build

    from_template = server.send(:read_resource, { uri: "ui://coffee-place-card/#{place.id}" }).first[:text]
    from_tool = CoffeePlaceCardTool.call(id: place.id).content.first[:resource][:text]

    expect(from_template).to eq(from_tool)
  end

  it "returns a readable not-found document rather than raising for an unknown id" do
    server = McpServer.build

    contents = server.send(:read_resource, { uri: "ui://coffee-place-card/999999" })

    expect(contents.first[:mimeType]).to eq("text/html;profile=mcp-app")
    expect(contents.first[:text]).to include("No coffee place found")
  end
end
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bundle exec rspec spec/mcp_server/server_spec.rb`
Expected: FAIL — 6 new examples fail; `capabilities[:extensions]` is `nil` and
`server.resources` is empty.

- [ ] **Step 3: Expose the two public entry points on the card tool**

In `mcp_server/tools/coffee_place_card_tool.rb`, inside `class << self` and
**above** the `private` keyword (currently line 97), add:

```ruby
    # Full card document for a place id, or nil when it does not exist. Shared by
    # the tool response path (Rails) and the MCP Apps resource-template path, so
    # there is exactly one card-rendering implementation.
    def card_html_for(id)
      place = CoffeePlace.find_by(id: id)
      place && card_html(place)
    end

    # The static MCP Apps shell. Filled in by Task 6; a minimal valid document
    # for now so registration and routing can be reviewed on their own.
    def template_html
      <<~HTML
        <!doctype html>
        <html>
          <head><meta charset="utf-8"></head>
          <body><div id="card-root"></div></body>
        </html>
      HTML
    end

    def not_found_html(id)
      "<!doctype html><html><body><p>No coffee place found with id #{ERB::Util.html_escape(id.to_s)}</p></body></html>"
    end
```

- [ ] **Step 4: Register the capability and both resources**

Replace `mcp_server/server.rb` with:

```ruby
# frozen_string_literal: true

require_relative "mcp_apps/bridge"
require_relative "tools/list_coffee_places_tool"
require_relative "tools/coffee_place_card_tool"
require_relative "tools/rate_coffee_place_tool"
require_relative "tools/set_favorite_drink_tool"

module McpServer
  # RFC 6570 level-1 template; the `mcp` gem matches `{id}` against one path
  # segment and hands `contents` the captured value.
  CARD_URI_TEMPLATE = "ui://coffee-place-card/{id}"

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
        uri: "ui://coffee-place-card/#{id}",
        mime_type: MCP::Apps::RESOURCE_MIME_TYPE,
        text: CoffeePlaceCardTool.card_html_for(id) || CoffeePlaceCardTool.not_found_html(id),
      )
    end
  end

  def self.rack_app(server = build)
    MCP::Server::Transports::StreamableHTTPTransport.new(server)
  end
end
```

Register the template resource exactly once, via `define_resource`. It both
appends to `@resources` (so `resources/list` advertises it) and backs the URI
with the content block (so `resources/read` serves it). Passing the same URI to
the constructor's `resources:` as well would list it twice; `MCP::Apps.ui_resource`'s
only added value is validating the `ui://` prefix of a constant we control, which
buys nothing here.

- [ ] **Step 5: Run the server spec to verify it passes**

Run: `bundle exec rspec spec/mcp_server/server_spec.rb`
Expected: PASS, 8 examples, 0 failures.

- [ ] **Step 6: Run the full suite — the Rails path must be undisturbed**

Run: `bundle exec rspec`
Expected: PASS, 83 examples, 0 failures. In particular
`spec/mcp_server/integration_spec.rb` and `spec/services/mcp/client_spec.rb`
must pass unmodified — they exercise the real Rails round trip.

- [ ] **Step 7: Commit**

```bash
git add mcp_server/server.rb mcp_server/tools/coffee_place_card_tool.rb spec/mcp_server/server_spec.rb
git commit -m "Declare the MCP Apps extension and register the card's ui:// resources

Adds the static template resource the tool links to and the per-place
ui://coffee-place-card/{id} resource template, both at
text/html;profile=mcp-app. The template path reuses card_html, so there is
one card-rendering implementation.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Dual-emit actions and refresh in place

The card's script gains the MCP Apps path alongside the Rails path. Under Rails
the iframe is replaced wholesale (the existing `NOTE` comment still holds); under
MCP Apps this same script instance survives, so it refreshes the card itself.

**Files:**
- Modify: `mcp_server/tools/coffee_place_card_tool.rb` (`card_script_js`, `card_html`)
- Test: `spec/mcp_server/tools/coffee_place_card_tool_spec.rb`

**Interfaces:**
- Consumes: `McpApps::Bridge.script` (Task 2); `card_script_js`, `card_html` (Task 1); `CARD_URI_TEMPLATE` shape from Task 4
- Produces: `card_script_js` additionally defines `applyCard(html)` and `refreshCard()`, and `sendAction` posts both message shapes. `card_html(place)` embeds `McpApps::Bridge.script` before `card_script_js` and passes the place id to the script as `var PLACE_ID = <id>;`.

Note: `card_script_js` now takes an argument — `card_script_js(place)`. Update
the call site in `card_html` from Task 1 accordingly.

- [ ] **Step 1: Write the failing test**

Append to `spec/mcp_server/tools/coffee_place_card_tool_spec.rb`:

```ruby
  it "emits both the Rails message shape and a real JSON-RPC tools/call per action" do
    place = CoffeePlace.create!(name: "Generic Cafe", address: "456 Elm St")

    html = described_class.call(id: place.id).content.first[:resource][:text]

    # Rails path, unchanged.
    expect(html).to include("window.parent.postMessage({ type: 'tool', payload:")
    # MCP Apps path.
    expect(html).to include("window.mcpApps.callTool(toolName, params)")
  end

  it "embeds the MCP Apps bridge and connects on load" do
    place = CoffeePlace.create!(name: "Generic Cafe", address: "456 Elm St")

    html = described_class.call(id: place.id).content.first[:resource][:text]

    expect(html).to include("window.mcpApps = {")
    expect(html).to include("'ui/initialize'")
    expect(html).to include("window.mcpApps.connect()")
  end

  it "refreshes itself in place by re-reading its own ui:// resource after an action" do
    place = CoffeePlace.create!(name: "Generic Cafe", address: "456 Elm St")

    html = described_class.call(id: place.id).content.first[:resource][:text]

    expect(html).to include("var PLACE_ID = #{place.id};")
    expect(html).to include("window.mcpApps.readResource('ui://coffee-place-card/' + PLACE_ID)")
    expect(html).to include("function applyCard(")
    # In-place DOM update, NOT an iframe reload.
    expect(html).to include("DOMParser")
    expect(html).not_to include("srcdoc")
  end

  it "routes both hosts' success paths through one toast/celebration function" do
    place = CoffeePlace.create!(name: "Generic Cafe", address: "456 Elm St")

    html = described_class.call(id: place.id).content.first[:resource][:text]

    # Called once from the MCP Apps promise chain and once from the Rails
    # message listener, so the two hosts cannot drift apart.
    expect(html.scan("handleActionSuccess(").length).to eq(3) # definition + 2 call sites
    expect(html).to include("handleActionSuccess(toolName, params);")
  end
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bundle exec rspec spec/mcp_server/tools/coffee_place_card_tool_spec.rb -e "emits both"`
Expected: FAIL — `expected ... to include "window.mcpApps.callTool(toolName, params)"`

- [ ] **Step 3: Rewrite `card_script_js` and update `card_html`**

Replace `card_script_js` (Task 1) with the version below. The Rails-path
listener body moves into `handleActionSuccess`, which both paths now call.

**Two existing assertions must be rewritten to match** — they currently name
expressions that no longer exist after the refactor. Their intent ("the reply is
self-describing; nothing depends on script-local state surviving the iframe
reload") is preserved, because `handleActionSuccess` is still fed from the
message's own fields. In `spec/mcp_server/tools/coffee_place_card_tool_spec.rb`:

- In `"reads the tool name and params from the tool-result message itself, not from script-local state"`,
  replace both expectations with:

  ```ruby
    expect(html).to include("handleActionSuccess(event.data.toolName, event.data.params)")
    expect(html).to include("function handleActionSuccess(toolName, params)")
    expect(html).to include("TOOL_LABELS[toolName]")
  ```

- In `"includes a night-sky celebration overlay that triggers only on a confirmed 5-star rating"`,
  replace the final expectation with:

  ```ruby
    expect(html).to include("toolName === 'rate_coffee_place' && params && params.rating === 5")
  ```

Change nothing else in that spec file. Every other existing example stays
untouched and must keep passing.

```ruby
    def card_script_js(place)
      <<~JS.chomp
        // Two hosts, two protocols, one card.
        //
        // Rails: the host does a full iframe.srcdoc replacement between sendAction
        // and the tool-result reply, so this script instance is NOT the one that
        // called sendAction — the reply must be self-describing.
        //
        // MCP Apps: this script instance survives; nothing reloads. The card
        // re-reads its own ui:// resource and swaps its own DOM instead.
        var TOOL_LABELS = #{TOOL_LABELS.to_json};
        var PLACE_ID = #{place.id};
        var CARD_URI = 'ui://coffee-place-card/' + PLACE_ID;

        function showToast(message) {
          var toast = document.getElementById('toast');
          toast.textContent = message;
          toast.style.display = 'block';
        }

        function hideToastSoon() {
          setTimeout(function () {
            var toast = document.getElementById('toast');
            if (toast) toast.style.display = 'none';
          }, 2000);
        }

        function showCelebration() {
          var el = document.getElementById('celebration');
          var starsContainer = el.querySelector('.celebration-stars');
          starsContainer.innerHTML = '';

          for (var i = 0; i < 18; i++) {
            var star = document.createElement('div');
            star.className = 'celebration-star';
            star.style.top = (Math.random() * 100) + '%';
            star.style.left = (Math.random() * 100) + '%';
            star.style.animationDelay = (Math.random() * 2) + 's';
            starsContainer.appendChild(star);
          }

          el.style.display = 'block';
        }

        function wireCelebration() {
          var el = document.getElementById('celebration');
          if (el) {
            el.addEventListener('click', function () { this.style.display = 'none'; });
          }
        }

        function handleActionSuccess(toolName, params) {
          var label = TOOL_LABELS[toolName] || 'Change';
          showToast(label + ' updated via MCP ✓');
          if (toolName === 'rate_coffee_place' && params && params.rating === 5) {
            showCelebration();
          }
        }

        // Swaps in freshly server-rendered card markup without reloading: the
        // fetched document's <style> and <body> replace this document's, and the
        // inline onclick="sendAction(...)" attributes keep working because this
        // script instance — and therefore sendAction — is still the live one.
        function applyCard(html) {
          var doc = new DOMParser().parseFromString(html, 'text/html');
          var style = doc.querySelector('style');
          var liveStyle = document.getElementById('card-style');
          if (style && liveStyle) liveStyle.textContent = style.textContent;

          var root = document.getElementById('card-root');
          var incoming = doc.getElementById('card-root');
          if (root && incoming) {
            root.innerHTML = incoming.innerHTML;
            wireCelebration();
          }
        }

        function refreshCard() {
          return window.mcpApps.readResource(CARD_URI).then(function (result) {
            var entry = (result && result.contents && result.contents[0]) || {};
            if (entry.text) applyCard(entry.text);
          });
        }

        function sendAction(toolName, params) {
          showToast('Saving…');

          // Rails: a custom shape the show view listens for. An MCP Apps host
          // ignores it (no `jsonrpc` field).
          window.parent.postMessage({ type: 'tool', payload: { toolName: toolName, params: params } }, '*');

          // MCP Apps: a real tools/call over the live MCP session. Rails ignores
          // it (no `type` field). `window.mcpApps` is absent only if the bridge
          // failed to load, so guard rather than throw inside an onclick.
          if (window.mcpApps && window.mcpApps.available) {
            window.mcpApps.callTool(toolName, params).then(function () {
              return refreshCard();
            }).then(function () {
              handleActionSuccess(toolName, params);
              hideToastSoon();
            }).catch(function (error) {
              showToast('Save failed: ' + (error.message || 'unknown error'));
              hideToastSoon();
            });
          }
        }

        wireCelebration();

        // Rails path: the reply arrives as a postMessage into the freshly
        // reloaded card, carrying the tool name and params with it.
        window.addEventListener('message', function (event) {
          if (!event.data || event.data.type !== 'tool-result') return;
          if (event.data.success) {
            handleActionSuccess(event.data.toolName, event.data.params);
          } else {
            showToast('Save failed: ' + (event.data.error || 'unknown error'));
          }
          hideToastSoon();
        });

        if (window.mcpApps && window.mcpApps.available) {
          window.mcpApps.connect().catch(function () { /* not an MCP Apps host */ });
        }
      JS
    end
```

Then update `card_html` (Task 1) so the card body is wrapped in `#card-root`,
the style tag is addressable, and the bridge loads first:

```ruby
    def card_html(place)
      <<~HTML
        <!doctype html>
        <html>
          <head>
            <meta charset="utf-8">
            <style id="card-style">
        #{card_styles_css(place).gsub(/^/, "      ")}
            </style>
          </head>
          <body style="font-family: sans-serif; margin: 0; padding: 0; max-width: 100vw; overflow-x: hidden;">
            <div id="card-root">
        #{card_body_html(place).gsub(/^/, "      ")}
            </div>
            <script>
        #{McpApps::Bridge.script.gsub(/^/, "      ")}
            </script>
            <script>
        #{card_script_js(place).gsub(/^/, "      ")}
            </script>
          </body>
        </html>
      HTML
    end
```

Add `require_relative "../mcp_apps/bridge"` at the top of
`mcp_server/tools/coffee_place_card_tool.rb`, after the frozen-string-literal
comment, so the tool spec (which requires the tool file directly) loads it.

- [ ] **Step 4: Run the card spec to verify it passes**

Run: `bundle exec rspec spec/mcp_server/tools/coffee_place_card_tool_spec.rb`
Expected: PASS, 20 examples, 0 failures. The pre-existing example
`"keeps the shop name and icon visible, in white, inside the celebration overlay"`
asserts `html.scan("Blue Bottle").length == 2`; the new wrapper div adds no
occurrences, so it still holds. If any pre-existing example fails, the change
altered rendered content — fix the implementation, not the assertion.

- [ ] **Step 5: Run the full suite**

Run: `bundle exec rspec`
Expected: PASS, 87 examples, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add mcp_server/tools/coffee_place_card_tool.rb spec/mcp_server/tools/coffee_place_card_tool_spec.rb
git commit -m "Dual-emit card actions: Rails postMessage plus real JSON-RPC tools/call

Under MCP Apps the iframe is never reloaded, so the card re-reads its own
ui:// resource and swaps its DOM in place instead of waiting for a srcdoc
replacement. Rails path untouched.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Fill in the shell template

`template_html` (a placeholder since Task 4) becomes the real shell: it
handshakes, learns the place id from `ui/notifications/tool-input`, reads
`ui://coffee-place-card/<id>`, and writes the card into itself.

**Files:**
- Modify: `mcp_server/tools/coffee_place_card_tool.rb` (`template_html`)
- Test: `spec/mcp_server/tools/coffee_place_card_tool_spec.rb`

**Interfaces:**
- Consumes: `McpApps::Bridge.script` (Task 2)
- Produces: `CoffeePlaceCardTool.template_html` → the shell document

- [ ] **Step 1: Write the failing test**

Append to `spec/mcp_server/tools/coffee_place_card_tool_spec.rb`:

```ruby
  describe ".template_html" do
    it "connects, then reads the per-place card once the host reports the tool's arguments" do
      html = described_class.template_html

      expect(html).to include("window.mcpApps.connect()")
      expect(html).to include("window.mcpApps.onToolInput(")
      expect(html).to include("'ui://coffee-place-card/' + args.id")
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
  end
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bundle exec rspec spec/mcp_server/tools/coffee_place_card_tool_spec.rb -e "template_html"`
Expected: FAIL — `expected ... to include "window.mcpApps.onToolInput("`

- [ ] **Step 3: Write the implementation**

Replace the placeholder `template_html` from Task 4 with:

```ruby
    # The static MCP Apps UI template. The host loads this once per tool call,
    # completes the handshake with it, then reports the tool's arguments via
    # `ui/notifications/tool-input`. Only then does the shell know WHICH place to
    # show, so it reads `ui://coffee-place-card/<id>` and installs that
    # server-rendered document — no card markup is duplicated in JavaScript.
    #
    # `document.write` rather than `innerHTML`: the fetched card carries its own
    # <script> (the bridge plus the card behavior), and script elements inserted
    # via innerHTML never execute.
    def template_html
      <<~HTML
        <!doctype html>
        <html>
          <head>
            <meta charset="utf-8">
          </head>
          <body style="font-family: sans-serif; margin: 0; padding: 1.25rem; color: #6b7280;">
            <div id="card-shell">Loading coffee place…</div>
            <script>
        #{McpApps::Bridge.script.gsub(/^/, "      ")}
            </script>
            <script>
              function installCard(html) {
                document.open();
                document.write(html);
                document.close();
              }

              function showShellError(message) {
                var shell = document.getElementById('card-shell');
                if (shell) shell.textContent = message;
              }

              window.mcpApps.onToolInput(function (args) {
                if (!args || args.id === undefined || args.id === null) {
                  showShellError('No coffee place id was provided.');
                  return;
                }

                window.mcpApps.readResource('ui://coffee-place-card/' + args.id).then(function (result) {
                  var entry = (result && result.contents && result.contents[0]) || {};
                  if (entry.text) {
                    installCard(entry.text);
                  } else {
                    showShellError('Could not load that coffee place.');
                  }
                }).catch(function (error) {
                  showShellError('Could not load that coffee place: ' + (error.message || 'unknown error'));
                });
              });

              window.mcpApps.connect().catch(function (error) {
                showShellError('Could not reach the host: ' + (error.message || 'unknown error'));
              });
            </script>
          </body>
        </html>
      HTML
    end
```

- [ ] **Step 4: Run the card spec to verify it passes**

Run: `bundle exec rspec spec/mcp_server/tools/coffee_place_card_tool_spec.rb`
Expected: PASS, 24 examples, 0 failures.

- [ ] **Step 5: Run the full suite**

Run: `bundle exec rspec`
Expected: PASS, 91 examples, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add mcp_server/tools/coffee_place_card_tool.rb spec/mcp_server/tools/coffee_place_card_tool_spec.rb
git commit -m "Fill in the MCP Apps shell template

Handshakes, learns the place id from ui/notifications/tool-input, then
installs the server-rendered card for that place.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: End-to-end verification

No automated harness can drive a real MCP Apps host's client runtime from this
suite — the same gap the Rails-side interactivity already has. This task pins
down what "working" means and records the result.

**Files:**
- Modify: `docs/superpowers/specs/2026-09-14-mcp-apps-native-interactivity-design.md` (append a "Verified" section)

- [ ] **Step 1: Confirm the whole suite is green**

Run: `bundle exec rspec`
Expected: PASS, 91 examples, 0 failures.

- [ ] **Step 2: Confirm the Rails demo still works, by hand**

Two terminals, as `README.md:33-38` documents:

```bash
bin/dev            # terminal 1 — Rails, http://localhost:3000
bin/mcp_server     # terminal 2 — the MCP server, http://localhost:3001
```

Open `http://localhost:3000/coffee_places/1`, click a star, and confirm the
toast reads "Rating updated via MCP ✓" and the card reflects the new rating.
Click the 5th star and confirm the celebration overlay appears. This is the
regression that matters most: Rails must be byte-for-byte as it was.

- [ ] **Step 3: Verify in Claude Desktop**

Point Claude Desktop at the MCP server, then ask it for a coffee place card.
Confirm, in order:

1. The card renders (not raw HTML, not a plain-text preview).
2. Clicking a star updates the stars **without the card blanking or reloading**.
3. The toast reads "Rating updated via MCP ✓".
4. Clicking the 5th star shows the celebration overlay.
5. Changing the favorite drink persists — re-asking for the card shows the new drink.
6. The database actually changed: `bin/rails runner 'p CoffeePlace.find(1).slice(:rating)'`.

If step 1 fails, inspect the `initialize` handshake: confirm the host declares
`io.modelcontextprotocol/ui` in `capabilities.extensions`, and that
`tools/list` shows `_meta.ui.resourceUri` on `get_coffee_place_card`. If the
host predates the Final spec, try
`MCP::Apps.tool_meta(resource_uri: TEMPLATE_URI, legacy: true)`, which also
emits the flat `"ui/resourceUri"` alias.

- [ ] **Step 4: Record the outcome in the design doc**

Append to `docs/superpowers/specs/2026-09-14-mcp-apps-native-interactivity-design.md`:

```markdown
## Verified

- `bundle exec rspec` — 91 examples, 0 failures (baseline before this work: 70).
- Rails demo: star click, toast, celebration, favorite drink — unchanged.
- Claude Desktop: <fill in what actually happened, including anything that did not work>.
```

Write what actually happened, including failures. Do not write "verified" for a
step that was not run.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/specs/2026-09-14-mcp-apps-native-interactivity-design.md
git commit -m "Record MCP Apps verification results

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Risks

- **The `document.write` install in the shell (Task 6) replaces the document
  that owns the bridge.** The fetched card re-embeds `McpApps::Bridge.script`
  and calls `connect()` again, so a fresh bridge comes up in the new document.
  Whether a host accepts a *second* `ui/initialize` from the same View is not
  specified. If Claude Desktop rejects it, the fallback is for the shell to keep
  ownership: inject only `<style>` and `#card-root` innerHTML (as `applyCard`
  already does in Task 5) and have the shell, not the card, own the behavior —
  serve the card body without its `<script>` on the resource-template path.
  Task 5's `applyCard` is already exactly that code path, so the fallback is a
  small change, not a rewrite.
- **`_meta.ui.resourceUri` support varies by host version.** `legacy: true`
  covers hosts predating the Final spec; see Task 7 Step 3.
- **Origin validation.** The ratified spec leaves `event.origin` validation
  unspecified and its own examples use `'*'`. The bridge follows the spec. Worth
  noting in the talk as an open question in the standard, not a bug here.
