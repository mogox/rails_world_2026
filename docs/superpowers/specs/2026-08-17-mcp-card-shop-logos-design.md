# MCP-UI coffee place card: shop logos

## Purpose

Demonstrate that the MCP server can enrich the MCP-UI card with more than
plain-text fields, using an inline SVG "shop logo" as the concrete example.
No new tool, resource, or transport plumbing — the logo is just more markup
inside the same HTML string `CoffeePlaceCardTool` already returns, so it
flows through `Mcp::Client` and the Rails show page unchanged.

## Design

- `CoffeePlaceCardTool` gains a `LOGOS` constant: a `Hash` from exact
  coffee place `name` to a small inline `<svg>` string, plus a
  `DEFAULT_LOGO` constant.
- `card_html` looks up `LOGOS.fetch(place.name, DEFAULT_LOGO)` and renders
  it above the place name.
- Three named places get distinct hand-made icons; everything else
  (existing or future coffee places) gets the default:
  - `"Blue Bottle"` — a mug icon, blue (`#2563eb`).
  - `"E2E Test Coffee"` — a to-go cup icon, green (`#16a34a`).
  - `"Live Test Coffee"` — a coffee bean icon, brown/orange (`#c2410c`).
  - default — a generic mug outline, gray (`#6b7280`).
- Icons are ~48×48, self-contained (no external image requests — everything
  MCP-UI renders must stay inline inside the sandboxed iframe), and use
  only basic shapes (`rect`, `path`, `ellipse`) — no external fonts or
  images.

## Tests

Extend `spec/mcp_server/tools/coffee_place_card_tool_spec.rb`:
- A coffee place named `"Blue Bottle"` gets the blue mug SVG (assert on a
  distinguishing fragment, e.g. its fill color).
- A coffee place with an unrecognized name gets the default gray SVG.

## Out of scope

- No persistence (no `logo` column, no file upload) — the mapping is a
  hardcoded, name-keyed lookup in the tool itself, matching the "read-only,
  demo enrichment" spirit of the rest of this branch.
- No change to `Mcp::Client`, the controller, or the view — the SVG is
  opaque HTML content to all of them.
