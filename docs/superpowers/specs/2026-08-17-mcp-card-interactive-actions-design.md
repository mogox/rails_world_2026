# MCP-UI card interactive actions: rating and favorite drink

## Purpose

Extend the coffee place card from a static, read-only MCP-UI resource into
an interactive MCP app: a user can submit a new star rating or change the
favorite drink directly from the card, and the change round-trips through
real MCP tool calls (not a Rails-only shortcut). This is a deliberate
reversal of two decisions from the original MCP server plan
(`2026-08-17-mcp-server-coffee-cards-design.md`): that build was
static-rendering-only and read-only tools only. Both constraints are
explicitly lifted here, for this feature, to demonstrate the full MCP-UI
action loop for a demo narrative.

## Architecture

```
Card (iframe, sandboxed, allow-scripts only)
   |  user clicks a star / picks a drink
   |  postMessage({type:"tool", payload:{toolName, params}}, "*")
   v
Rails host JS (show.html.erb) — listens on window, filters on event.source === iframe.contentWindow
   |  fetch POST /coffee_places/:id/mcp_action  { tool_name, params }  (CSRF token, JSON)
   v
CoffeePlacesController#mcp_action
   |  allowlist check: tool_name in %w[rate_coffee_place set_favorite_drink]
   |  Mcp::Client#call_action(tool_name, params) :
   |      1. calls the write tool on the MCP server
   |      2. on success, calls get_coffee_place_card again for fresh HTML
   v
Rails responds { html: "<fresh card>" } or { error: "..." } (422)
   v
Host JS replaces iframe.srcdoc with the fresh html; once the new iframe's
`load` event fires, posts {type:"tool-result", success, error?} into it
   v
The new card's own inline script (present in every render) shows a
"Saved via MCP ✓" / error toast on receiving that reply
```

**Trust boundary:** the sandboxed iframe (`sandbox="allow-scripts"`, no
`allow-same-origin`) never makes a network request itself — it has no
cookies, no CSRF token, and posting a message is the only channel out. The
parent page is the only thing that ever makes the real, authenticated
request, and only after checking the requested tool name against a
server-side allowlist. A compromised or buggy card can request an action;
it cannot perform one.

**No message-id correlation:** the card and the post-reload card are two
separate DOM/script instances (a full `srcdoc` replacement, not a live
patch), so there is no in-page state to correlate a specific request with
its reply across the reload. Given this app has exactly one save in flight
at a time, the host simply posts `tool-result` once into the freshly
loaded iframe rather than round-tripping a message id — sufficient for
this scope, called out explicitly as a simplification.

## Components

### `mcp_server/tools/rate_coffee_place_tool.rb` (new)

`MCP::Tool` subclass, `tool_name "rate_coffee_place"`. `input_schema`
requires `id` (integer) and `rating` (integer). `.call(id:, rating:)`
finds the place, assigns `rating`, and:
- on `place.save` success: `MCP::Tool::Response.new([{type: "text", text: "Rating updated"}])`.
- on validation failure (out of the model's existing `1..5` range):
  `MCP::Tool::Response.new([{type: "text", text: place.errors.full_messages.to_sentence}], error: true)`.
- not-found `id`: same not-found pattern as `CoffeePlaceCardTool`.

### `mcp_server/tools/set_favorite_drink_tool.rb` (new)

`MCP::Tool` subclass, `tool_name "set_favorite_drink"`. `input_schema`
requires `id` (integer); `beverage_type` (string) and `beverage_id`
(integer) are optional — both blank clears the favorite drink.
`.call(id:, beverage_type: nil, beverage_id: nil)` mirrors
`CoffeePlacesController#assign_favorite_drink`'s allowlist
(`%w[Coffee Tea]`) before ever calling `.constantize`, finds the place,
assigns `favorite_drink` (or `nil`), saves, returns success/error text the
same shape as above.

### `app/services/mcp/client.rb` (modified)

- Extract the existing connect/call/close/rescue logic in
  `#coffee_place_card` into a private `with_connected_client(&block)` that
  yields a connected `MCP::Client`, and still does the
  `ConnectionError`/`ensure`-safe-close handling exactly as today.
  `#coffee_place_card` becomes a thin caller of it.
- Add `#call_action(tool_name, params)`: inside
  `with_connected_client`, calls `tool_name` with `params`, raises
  `ToolError` (via the existing `error_text` helper) if that call's
  `isError`, otherwise calls `get_coffee_place_card` with `params[:id]`
  and returns its HTML the same way `#coffee_place_card` does. Same two
  exception classes as today; no new ones.

### `config/routes.rb` / `app/controllers/coffee_places_controller.rb` (modified)

- `resources :coffee_places, ...` gains a member route:
  `post :mcp_action` → `POST /coffee_places/:id/mcp_action`.
- `#mcp_action`: validates `params[:tool_name]` against
  `ALLOWED_MCP_ACTIONS = %w[rate_coffee_place set_favorite_drink].freeze`
  (422 JSON error if not allowlisted), loads the `CoffeePlace` (404 via
  the normal `find` if missing), calls
  `Mcp::Client.new.call_action(tool_name, params[:params].to_unsafe_h.symbolize_keys.merge(id: coffee_place.id))`,
  renders `{ html: }` on success or `{ error: e.message }` (422) on
  `Mcp::Client::ConnectionError`/`ToolError`.

### `mcp_server/tools/coffee_place_card_tool.rb` (modified)

- Each shop's `LOGO` constant is paired with an `ACCENT` hex (reusing the
  same color); `DEFAULT_ACCENT` for the fallback.
- The card gets a wrapping `<div>` with a colored top border
  (`border-top: 4px solid <accent>`), rounded corners, and a subtle
  shadow — the visual-polish pass.
- The `★★★★★` rating text becomes 5 `<button>` elements
  (`type="button"`, minimal/unstyled via inline CSS so they read as plain
  glyphs, not chrome-y buttons), each calling
  `sendAction('rate_coffee_place', {id, rating: N})` on click.
- The favorite-drink `<p>` becomes a `<select>` built from
  `Beverage.order(:type, :name)`, grouped by type, using the same
  `"Type-id"` encoded option-value convention the main Rails form already
  uses (`app/views/coffee_places/new.html.erb`) — kept consistent rather
  than inventing a second encoding. On `change`, calls
  `sendAction('set_favorite_drink', {id, beverage_type, beverage_id})`
  (empty selection → both `null`).
- An inline `<script>` (present in every render, so it's live again
  immediately after a reload) defines `sendAction(toolName, params)`
  (shows a "Saving…" toast, then `postMessage`s to `window.parent`) and a
  `message` listener that shows "Saved via MCP ✓" or the error text on a
  `tool-result` reply.

### `app/views/coffee_places/show.html.erb` (modified)

- The iframe gets `id="coffee-place-card"`.
- A `<script>` block (outside the iframe, in the host page) listens for
  `message` events, filters to `event.source === iframe.contentWindow`
  and `event.data.type === "tool"`, does the `fetch` to
  `mcp_action_coffee_place_path`, swaps `iframe.srcdoc` on success, and
  posts the `tool-result` reply into the reloaded iframe once its `load`
  event fires (error path posts `tool-result` with `success: false`
  directly, no reload needed since nothing changed).

## Tests

- `spec/mcp_server/tools/rate_coffee_place_tool_spec.rb` (new): valid
  rating updates the record and returns success; out-of-range rating
  returns a validation error; unknown id returns the not-found error.
- `spec/mcp_server/tools/set_favorite_drink_tool_spec.rb` (new): setting a
  valid `Coffee`/`Tea` updates the association; a disallowed type is
  rejected the same way `assign_favorite_drink` rejects it today; a blank
  `beverage_id` clears the favorite drink; unknown place id returns the
  not-found error.
- `spec/services/mcp/client_spec.rb` (extended): `#call_action` success
  (write then refetch, returns the refetched HTML); write-tool failure
  raises `ToolError` without attempting the refetch; refetch failure after
  a successful write also raises `ToolError`. The `with_connected_client`
  refactor must not change `#coffee_place_card`'s existing 5 example
  behaviors (regression, not just new coverage).
- `spec/requests/coffee_places_spec.rb` (extended): `POST
  /coffee_places/:id/mcp_action` with an allowlisted `tool_name` (stub
  `Mcp::Client#call_action`) returns `{html:}`; a non-allowlisted
  `tool_name` returns 422 without ever constructing `Mcp::Client`; a
  `Mcp::Client::ConnectionError`/`ToolError` from the stub returns 422
  with an `error` body.
- Manual/browser verification (not rspec — this is JS message-passing):
  drive a real Chrome browser to a coffee place's show page, click a star,
  confirm the card shows "Saving…" then "Saved via MCP ✓" and the rating
  visibly updates; change the favorite-drink select and confirm the same;
  confirm the DB record actually changed (e.g. via `bin/rails runner`).

## Out of scope

- No optimistic local update before the server round-trip beyond the
  "Saving…" toast text itself — the visible rating/drink only change once
  the fresh card HTML arrives.
- No concurrent-action handling (message-id correlation, request
  cancellation, disabling the controls while a save is in flight beyond
  the toast text) — single sequential action at a time, matching the
  "no message-id correlation" note in Architecture.
- No new MCP resources or tools beyond the two write tools — `list_coffee_places`
  and `get_coffee_place_card` are unchanged in shape (`get_coffee_place_card`'s
  HTML output changes, not its interface).
- No authorization/ownership model (any visitor can rate any place) —
  matches the rest of this demo app, which has no user accounts.
