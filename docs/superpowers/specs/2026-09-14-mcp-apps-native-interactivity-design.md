# Native interactivity for MCP Apps-compliant hosts (e.g. Claude Desktop)

## Purpose

The coffee place card renders correctly as static HTML in any MCP host,
including Claude Desktop, but is only *interactive* inside this app's
own Rails page. In Claude Desktop, clicking a star fires the card's
`postMessage`, but nothing is listening for that message's shape, so
nothing visibly happens.

Root cause (confirmed by inspecting the actual `initialize` handshake
Claude Desktop sends, and researching the current spec): Claude Desktop
implements the official **MCP Apps** extension
(`io.modelcontextprotocol/ui`, mimeType `text/html;profile=mcp-app`) — a
different, newer, more structured protocol than the "MCP-UI" community
convention (`mcpui.dev` / `mcp_ui_server`) this branch built against.
Two concrete gaps:

1. **Tool→resource linkage.** MCP Apps expects a tool's *definition* to
   declare `_meta.ui.resourceUri`, and the host fetches that resource
   *separately* via `resources/read`. We currently embed the card's HTML
   directly inside `get_coffee_place_card`'s tool response — nothing
   links the tool to an independently-fetchable `ui://` resource.
2. **mimeType.** The spec wants `text/html;profile=mcp-app`;
   `mcp_ui_server` sends plain `text/html`.

Given the mismatch, Claude Desktop most likely never invokes its
interactive "app" surface for our card at all — it just shows the raw
HTML as a preview.

This design adds real interactivity for MCP Apps-compliant hosts
**without changing anything about how the Rails demo works today**. Rails
is not itself an MCP Apps host (no persistent MCP session, no JSON-RPC
proxying) and is not being rebuilt into one. Both integrations keep
working, side by side, from the same tools and the same card.

## Context: why this branch built on MCP-UI, not MCP Apps, in the first place

Worth recording plainly, since it explains both how we got here and why
the plan below is additive rather than a do-over.

- **Not a timing gap.** MCP Apps was proposed Nov 21, 2025 (SEP-1865) and
  officially ratified Jan 26, 2026. This project's original design work
  happened in August 2026 — MCP Apps had already been the official
  standard for roughly seven months. The mismatch isn't "MCP Apps didn't
  exist yet."
- **What actually happened:** the original request asked for an
  "MCP-app using MCP-UI paradigm." Researching "MCP-UI" at the time found
  `mcpui.dev` / `mcp_ui_server` directly — a real, working Ruby gem that
  matched the terminology exactly. That research didn't separately check
  whether the community convention it implements had since been folded
  into something official with different wire details. A genuine gap in
  the original research, not a deliberate choice to use an older
  approach over a newer one.
- **The two aren't really "old vs. new."** Per the MCP Apps spec history,
  MCP Apps is a merge of the community MCP-UI project and OpenAI's Apps
  SDK, authored jointly with Anthropic, OpenAI, and the MCP-UI
  maintainers — MCP-UI is now officially described as MCP Apps' reference
  implementation, not a legacy alternative. That description fits the
  mature JS/TS `@mcp-ui/server`/`@mcp-ui/client` packages. The **Ruby
  port, `mcp_ui_server`, is still v0.1.0** — early enough that it
  plausibly hasn't caught up to the newer official wire details (the
  `text/html;profile=mcp-app` mimeType, the tool-level
  `_meta.ui.resourceUri` linkage) yet. It implements the original,
  simpler embedded-resource convention.
- **There is no Ruby MCP Apps SDK to reach for instead.** Confirmed:
  `@modelcontextprotocol/ext-apps` (`registerAppTool`,
  `registerAppResource`, the client-side `App` class) requires Node.js
  20+ and is TypeScript/JS-first; no Ruby equivalent exists. The plan
  below — using the base `mcp` gem's generic primitives directly and
  hand-rolling the JSON-RPC-over-postMessage framing — isn't working
  around a library we missed. It's the only path available for a
  Ruby-based MCP server today.

## Architecture

```
                    ┌─ Rails (existing, unchanged) ──────────────┐
                    │  postMessage({type:"tool", payload:{...}}) │
                    │  → /coffee_places/:id/mcp_action            │
                    │  → Mcp::Client#call_action                  │
                    │  → full iframe.srcdoc replacement            │
                    └───────────────────────────────────────────┘
Card's own script ──┤
                    ┌─ MCP Apps host, e.g. Claude Desktop (new) ──┐
                    │  postMessage(JSON-RPC 2.0 tools/call)        │
                    │  → host proxies over the LIVE MCP session    │
                    │    directly to our MCP server (no Rails      │
                    │    backend involved at all)                  │
                    │  → JSON-RPC result posted back, SAME iframe  │
                    │    instance (no reload)                      │
                    └───────────────────────────────────────────┘
```

The card emits **both** message shapes on every action. A given host's
listener only recognizes one shape (Rails checks `event.data.type ===
"tool"`; an MCP Apps host's client runtime checks for a `jsonrpc` field)
and silently ignores the other — so the same server-rendered HTML works
correctly in either environment without needing to detect which one it's
in.

## Server-side changes (`mcp_server/`)

- **`CoffeePlaceCardTool`** gains `_meta: { ui: { resourceUri:
  "ui://coffee-place-card/{id}" } }` on its tool definition (the `mcp`
  gem's `MCP::Tool.meta(...)` DSL supports this — confirmed by reading
  `lib/mcp/tool.rb`). This is the signal a compliant host uses to decide
  "call this tool, then render its linked resource as an app" instead of
  showing plain text.
- The tool's *response* content is unchanged — Rails keeps working
  exactly as it does today, reading the embedded resource the same way.
- Add a resource template registration for `ui://coffee-place-card/{id}`
  so the card is independently fetchable via `resources/read`, as MCP
  Apps requires. The `mcp` gem supports this two ways — `resources_read_handler`
  (a catch-all block, parse the id out of the requested URI string) or the
  more idiomatic `define_resource_template(uri_template:
  "ui://coffee-place-card/{id}")` (RFC 6570 templates, `@resource_templates`
  in the gem). Prefer the latter; both are confirmed present in the gem.
  Extract `CoffeePlaceCardTool`'s HTML-building into a method both the
  tool-call path and this new resource-template path call, so there is
  one card-rendering implementation, not two.
- The resource served via this new path uses mimeType
  `text/html;profile=mcp-app`, not the tool-response resource's existing
  `text/html`.
- `rate_coffee_place` and `set_favorite_drink` need no `_meta` changes —
  they're plain callable tools invoked *from inside* the running app,
  not tools that themselves render UI.

## Implementation shape: gem-extraction-ready, not a gem (yet)

There is currently no Ruby SDK for MCP Apps at all — `@modelcontextprotocol/ext-apps`
is Node.js/TypeScript-only. That's a real gap, and this implementation
would be a legitimate candidate to extract into a small open-source gem
later.

Not now, though. A gem is the wrong unit of work with only one consumer
(this coffee card) — its API would be guessed at rather than generalized
from real usage, and gem packaging (gemspec, versioning, README,
publishing decisions) is overhead this branch doesn't need to carry
before the talk. This also matches every other YAGNI call already made
on this branch (no `@modelcontextprotocol/ext-apps` bundling, no
concurrent-action handling, etc.).

Middle ground: write the generic pieces — the tool `_meta.ui.resourceUri`
helper, the resource-template registration, JSON-RPC envelope
construction — as a small, self-contained internal module (e.g.
`mcp_server/mcp_apps/` or an `McpApps` namespace) with no dependency on
coffee-place-specific types, rather than inlining them directly into
`CoffeePlaceCardTool`. `CoffeePlaceCardTool` becomes a *consumer* of that
module, the same shape it would have as a gem's client. This costs
nothing extra to build correctly and means a future gem extraction is a
clean lift (move the directory, add a gemspec) rather than a rewrite —
without committing to packaging or publishing anything now.

## Card-side changes (`mcp_server/tools/coffee_place_card_tool.rb`'s embedded script)

- `sendAction` (or a renamed dual-purpose function) posts **two**
  messages per action: the existing custom shape (for Rails) and a real
  `{"jsonrpc":"2.0","id":<n>,"method":"tools/call","params":{"name":
  toolName,"arguments":params}}` message, with `id` a simple incrementing
  counter (no need for a request queue — this app never has more than one
  action in flight, matching the existing "single sequential action"
  scope decision from the original interactive-actions design).
- A new listener recognizes a JSON-RPC-shaped reply
  (`{"jsonrpc":"2.0","id":..., "result":...}` matching the last sent
  `id`) separately from the existing Rails-shaped `tool-result` listener.
- Under MCP Apps, a real host does not reload the iframe between the
  request and the reply — the app is expected to update its own DOM in
  place. The spec's overview confirms Views can both "Call server tools
  (`tools/call`)" *and* "Read server resources (`resources/read`)" —
  re-fetching a resource from inside the app is a documented protocol
  capability, not something we'd be working around. Plan: once a
  JSON-RPC tool-call result arrives, re-fetch the card's own resource
  URI (`ui://coffee-place-card/{id}`) via the same JSON-RPC-over-
  postMessage channel (a `resources/read` request, same `id`-correlation
  approach as `tools/call`) and replace the *current* document's content
  in-place (not `iframe.srcdoc` — there is no reload). This reuses 100%
  of the existing server-rendered card, no duplicated rendering logic in
  JS, and the toast/celebration logic already in the (never-reloaded)
  script instance can fire directly — sidestepping the whole "state
  doesn't survive reload" class of bug this branch hit twice already.
  **Remaining unknown, small in scope:** the exact response envelope
  shape for a `resources/read` reply (confirming it matches the `{uri,
  mimeType, text}` shape already handled elsewhere) — a quick check
  against the spec's JSON-RPC examples during implementation, not a
  feasibility risk.
- We are **not** bundling the official `@modelcontextprotocol/ext-apps`
  npm client library into the server-rendered HTML (CSP/bundling
  complexity, and it's a Node package with no natural place to vendor it
  from a Ruby app without a JS build step this project doesn't have).
  The JSON-RPC-over-postMessage framing is simple enough to hand-write,
  matching how this branch already hand-wrote its own protocol instead
  of adopting `@mcp-ui/client`.

## Rails: no changes

`app/views/coffee_places/show.html.erb` and `Mcp::Client#call_action`
are untouched. Rails never sees or reacts to the JSON-RPC-shaped
messages; it keeps working exactly as today, verified by the existing
test suite continuing to pass unmodified.

## Tests

- `mcp_server` tool spec: assert `CoffeePlaceCardTool`'s tool definition
  includes the `_meta.ui.resourceUri` value.
- A resource-template spec: calling the registered template/handler for
  `ui://coffee-place-card/<id>` returns the same HTML
  `CoffeePlaceCardTool.call(id:)` embeds, with mimeType
  `text/html;profile=mcp-app`, and a not-found id behaves sensibly (no
  crash).
- Card spec: assert both message shapes are present in the emitted
  script (the existing custom shape, unchanged, plus the new JSON-RPC
  one), and that the existing Rails-path tests (which were the point of
  the two earlier bug-hunts this session) still pass unmodified —
  regression coverage that the additive change didn't disturb the
  working Rails path.
- Manual verification: live-tested in Claude Desktop, since there is no
  automated way to drive a real MCP Apps host's client runtime from this
  test suite (same category of gap the Rails-side interactivity already
  has — verified live, not exercised by rspec).

## Out of scope

- No change to the Rails demo's architecture or protocol.
- No support for concurrent/overlapping actions (matches the existing
  "single sequential action" scope decision).
- No adoption of the official `@modelcontextprotocol/ext-apps` client
  library — hand-rolled JSON-RPC-over-postMessage framing instead, kept
  minimal.
- No gem extraction/packaging/publishing — the internal module described
  above is written so that extraction stays *possible* later, not done
  now.
- No changes to `rate_coffee_place`/`set_favorite_drink`'s tool
  definitions.

## Verified

Recorded 2026-09-14, after implementing this design.

### Automated

`bundle exec rspec` — **107 examples, 0 failures** (baseline before this work: 70).

Read that number honestly. Six of the new examples test real Ruby behaviour (resource
registration, routing, and the byte-equality of the tool's HTML against the resource
template's). The rest assert that byte sequences appear in generated JavaScript that
**nothing in this repo executes**. The bridge and card scripts are a manually-verified
surface; the Claude Desktop pass below is their real gate.

### Rails demo — verified live, unchanged

Booted an isolated pair (Rails on 3010, MCP server on 3011) and drove it in Chrome.
The card rendered correctly: shop name, address, five rating buttons reflecting the
stored rating, and the favorite-drink select. Exercised the real action round trip
through `Mcp::Client#call_action`: a `rate_coffee_place` call moved place 1 from 5 to
3, the write committed to the database, and the freshly returned card carried exactly
three filled and two empty rating buttons. Reloading the page showed the new rating.
The rating was restored to its original value afterwards.

Not verified in the browser: the `postMessage` click wiring itself. The demo's iframe
is sandboxed without `allow-same-origin`, so automated tooling cannot reach inside it.
The server-side half of that path is fully exercised above, and
`app/views/coffee_places/show.html.erb` is untouched by this work.

### MCP Apps surfaces — verified at the protocol level

Driven through `MCP::Server#handle`, i.e. the same path the HTTP transport uses:

| Request | Result |
|---|---|
| `initialize` | `capabilities.extensions` → `{"io.modelcontextprotocol/ui" => {mimeTypes: ["text/html;profile=mcp-app"]}}` |
| `tools/list` | `get_coffee_place_card` carries `_meta` → `{ui: {resourceUri: "ui://coffee-place-card/template"}}` |
| `resources/read ui://coffee-place-card/template` | `text/html;profile=mcp-app`; shell contains both `ui/initialize` and `onToolInput` |
| `resources/read ui://coffee-place-card/1` | `text/html;profile=mcp-app`; real card content |
| `resources/templates/list` | `["ui://coffee-place-card/{id}"]` |

The View-side handshake was found non-conformant during the final review and corrected:
`ui/initialize` now sends all three required params (`appInfo`, `appCapabilities`,
`protocolVersion`), verified present in both the shell and the per-place card. The
reference host validates these with a non-passthrough schema, so the original
single-param request would have been rejected outright — the feature would not have
worked in its target host. A protocol-conformance example now pins the param set.

### Claude Desktop — verified, 2026-09-15

**The card renders as an interactive app and responds to input in Claude Desktop.**
Confirmed by hand; driving a real MCP Apps host's client runtime is not something the
test suite or an automated browser can do.

Two failures preceded the passing run, both environmental rather than design faults,
and both worth recording because they cost real time:

- The server answering on port 3001 was a **stale process from another branch**
  (`mcp-server-ui-cards`), started days earlier. It responded correctly to
  `initialize` — so it did not look dead — but advertised no `capabilities.extensions`
  and served the pre-branch card. Any MCP Apps verification against it was guaranteed
  to fail while looking like a code problem.
- That process ran out of the git worktree `.worktrees/mcp-server-ui-cards`, which has
  **its own database**. Ids that worked against it (place 13, "Saint Frank Coffee")
  do not exist in this repo's database at all.

Before trusting a host-side result, confirm the server you are talking to is the build
you think it is: `initialize` must return `capabilities.extensions` containing
`io.modelcontextprotocol/ui`, and the served card must contain `window.mcpApps`.

The `document.write` reinit risk this design worried about is largely retired: the
reference host bridge explicitly tolerates a second `ui/initialize` from the same
frame, logging a double-mount warning and replacing the previous `appInfo`. The
`document.write` install therefore stands, and the verified run above exercised it —
the card installed and stayed interactive, so the second handshake was accepted in
practice, not just in theory. Should another host refuse it, a failure is diagnosable
rather than silent — the handshake is
bounded at 10 seconds, a failed handshake is terminal and rejects both queued and
subsequent calls, every failure path writes to `console.error`, and the shell shows a
visible error rather than sitting on "Loading coffee place…". If it does fail, the
documented fallback is to keep the bridge in the shell and inject only styles plus
`#card-root`'s markup — `applyCard` in the card script is already exactly that code path.
