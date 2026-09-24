# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...

## MCP server (coffee place cards)

This app includes a standalone MCP server (`mcp_server/`) that exposes
coffee-spots data as MCP tools, including one that returns an MCP-UI HTML
card for a coffee place. The Rails app calls it as an MCP client and
renders the card on each coffee place's page.

To see it end to end, run both processes:

```console
$ bin/rails server       # terminal 1 — the Rails app, http://localhost:3000
$ bin/mcp_server          # terminal 2 — the MCP server, http://localhost:3001
```

Then visit `http://localhost:3000`, click a coffee place, and its page will
render the card served by the MCP server inside a sandboxed iframe. Stop
`bin/mcp_server` and reload the page to see the fallback (plain attributes)
path instead.
