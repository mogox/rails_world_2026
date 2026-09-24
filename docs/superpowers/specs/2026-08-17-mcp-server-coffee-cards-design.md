# MCP server + MCP-UI coffee place cards

## Purpose

Add a standalone MCP server to this repo, on its own branch, that the
Rails app calls as an MCP client. The server exposes coffee-spots data as
MCP tools; one of them returns an [MCP-UI](https://mcpui.dev) resource — an
HTML "card" for a coffee place — which the Rails app fetches and renders in
a sandboxed iframe on that coffee place's new show page. This exercises the
full loop: MCP server → MCP-UI resource → MCP client (Rails) → rendered UI.

## Architecture

Two OS processes sharing one repo and one SQLite database:

- **`coffee_spots`** (existing Rails app, `bin/rails server`, port 3000) —
  the **MCP client**.
- **`mcp_server/`** (new, `bin/mcp_server`, port 3001) — the **MCP server**.
  Not a Rails app itself: a plain Ruby process that boots the existing
  `config/environment.rb` at startup (so it gets `CoffeePlace` /
  `Beverage` / `Coffee` / `Tea` and the app's DB connection for free — no
  duplicated models, no second Gemfile), then starts an MCP server over the
  **Streamable HTTP** transport (the standard remote-MCP transport) using
  the official `mcp` gem, listening on `ENV.fetch("MCP_SERVER_PORT", 3001)`.

Request flow for a coffee place's show page:

1. Browser requests `/coffee_places/:id`.
2. `CoffeePlacesController#show` uses `Mcp::Client` to connect to the MCP
   server, call the `get_coffee_place_card` tool with that id, and close
   the session. (Connect → call → close per request — the transport's
   session state lives in the server process's memory, so there is no
   cross-request session to reuse from the Rails side.)
3. The tool looks up the `CoffeePlace`, builds a small HTML fragment (name,
   address, star rating, favorite drink), and returns it via
   `McpUiServer.create_ui_resource(uri: "ui://coffee-place-card/:id",
   content: { type: :raw_html, htmlString: html }, encoding: :text)`.
4. The Rails client extracts the HTML from the resource and the view
   embeds it via `content_tag(:iframe, "", srcdoc: html, sandbox:
   "allow-scripts")` — sandboxed, no `allow-same-origin`, per MCP-UI's
   security model (the iframe content runs in an opaque origin with
   scripting allowed but no access to the parent document or cookies).
5. If the MCP server is unreachable, the show page falls back to a plain
   Rails-rendered view of the record's attributes with a notice, instead
   of erroring.

Interactivity (the iframe posting messages back to the host) is out of
scope — see "Out of scope" below.

## Components

### Gemfile

Add to the root group (used by both processes, since `mcp_server/` boots
via the app's own bundle):

```ruby
gem "mcp"            # official Ruby MCP SDK: client (Rails) + server (mcp_server/)
gem "mcp_ui_server"   # McpUiServer.create_ui_resource
```

### MCP server (`mcp_server/`)

- `mcp_server/tools/list_coffee_places_tool.rb` — `MCP::Tool` subclass,
  `list_coffee_places`: text summary of all coffee places (id, name,
  address, rating). No arguments. Gives the server a second, non-UI tool
  so `get_coffee_place_card` isn't the only thing it does.
- `mcp_server/tools/coffee_place_card_tool.rb` — `MCP::Tool` subclass,
  `get_coffee_place_card`, `input_schema` requires `id`. Finds the
  `CoffeePlace`; builds the HTML card (name, address, rating rendered as
  stars, favorite drink name + type if present); returns
  `MCP::Tool::Response.new([ui_resource])`. If the id doesn't resolve to a
  record, returns an MCP tool error (`is_error: true` with a text
  message) rather than raising.
- `mcp_server/server.rb` — builds `MCP::Server.new(name: "coffee_spots_mcp",
  tools: [ListCoffeePlacesTool, CoffeePlaceCardTool])`, wraps it in
  `MCP::Server::Transports::StreamableHTTPTransport.new(server)`, serves it
  as a Rack app via Puma (single-process/single-worker — the transport
  keeps session state in memory).
- `bin/mcp_server` — executable script: `require_relative
  "../config/environment"`, then `require_relative "../mcp_server/server"`
  and start it. Run in a second terminal alongside `bin/rails server` (or
  `bin/dev`).

### Rails client side

- `app/services/mcp/client.rb` — wraps `MCP::Client::HTTP` +
  `MCP::Client`. Connects to `ENV.fetch("MCP_SERVER_URL",
  "http://localhost:3001")`. `#coffee_place_card(id)` calls the
  `get_coffee_place_card` tool and returns the extracted HTML string
  (handles both `text` and base64 `blob` resource encodings per the
  MCP-UI spec). Raises `Mcp::Client::ConnectionError` (a narrow wrapper
  around the underlying connection failure) on network failure; always
  closes the session in an `ensure`.
- `config/routes.rb` — add `:show` to `resources :coffee_places` (currently
  `only: [:index, :new, :create]`).
- `CoffeePlacesController#show` — loads the record; calls `Mcp::Client`;
  on success sets `@card_html`; on `Mcp::Client::ConnectionError` sets
  `@mcp_unavailable = true` and the view falls back to plain attributes.
- `app/views/coffee_places/show.html.erb` — renders the sandboxed iframe
  when `@card_html` is present, otherwise a "live card unavailable" notice
  plus the coffee place's plain fields.
- `app/views/coffee_places/index.html.erb` — link each coffee place's name
  to its new show page.

### Tests

- `spec/mcp_server/tools/list_coffee_places_tool_spec.rb` and
  `.../coffee_place_card_tool_spec.rb` — call the tool classes' `.call`
  directly (via `rails_helper`, real test DB), asserting on the returned
  resource's `uri`, `mimeType`, and HTML content, plus the not-found path.
- `spec/services/mcp/client_spec.rb` — unit-tests the wrapper's
  response-parsing (text and blob encodings) and error handling against a
  stubbed transport/client — no real second process involved.
- `spec/requests/coffee_places_show_spec.rb` — stubs `Mcp::Client` to cover
  both the iframe-rendered path and the connection-error fallback path.
- README gets a short "running both processes" section documenting
  `bin/mcp_server` + `bin/rails server` for manual end-to-end
  verification (the automated suite never runs both processes together).

## Out of scope

- No postMessage/JSON-RPC handling for messages the iframe sends back to
  the host — this build is one-directional (server → UI → rendered),
  matching the "static rendering only" scope decision.
- No write tools (create/update coffee places) on the MCP server — read
  only, matching the "direct DB read" data-access decision.
- No production deployment/process-manager concerns for `mcp_server/`
  (e.g. Procfile, systemd) — `bin/mcp_server` run manually in a second
  terminal is sufficient for this branch's goal.
- No MCP Inspector / CORS setup — the only caller is the Rails app itself
  (server-to-server), not a browser connecting to the MCP server directly.
