require "rails_helper"
require_relative "../../../mcp_server/mcp_apps/bridge"

# Nothing in this suite executes JavaScript: `McpApps::Bridge.script` is a
# string, and every example below asserts that a byte sequence appears in that
# generated source. That is a real guard against the source silently losing a
# line, but it is NOT evidence that the bridge behaves as described at runtime —
# so each example says what it inspects rather than what a host would observe.
# The one example anchored to observable behavior is the conformance example at
# the bottom, which pins the ui/initialize params to the ratified schema.
RSpec.describe McpApps::Bridge do
  let(:script) { described_class.script }

  it "emits a ui/initialize request and the matching initialized notification" do
    expect(script).to include("'ui/initialize'")
    expect(script).to include("'ui/notifications/initialized'")
    expect(script).to include("appCapabilities")
  end

  it "emits tools/call and resources/read helpers" do
    expect(script).to include("'tools/call'")
    expect(script).to include("'resources/read'")
    expect(script).to include("callTool")
    expect(script).to include("readResource")
  end

  it "emits id-keyed reply correlation and a jsonrpc guard on the listener" do
    expect(script).to include("jsonrpc")
    expect(script).to include("pending[")
    expect(script).to include("nextId")
  end

  it "emits a tool-input branch that fans out to registered callbacks" do
    expect(script).to include("'ui/notifications/tool-input'")
    expect(script).to include("onToolInput")
  end

  it "emits a pre-handshake request queue" do
    expect(script).to include("queue")
    expect(script).to include("ready")
  end

  it "is free of coffee-place-specific vocabulary so it can be extracted as-is" do
    expect(script).not_to match(/coffee|rating|drink|celebration/i)
  end

  it "emits an event.source check so only the host frame can drive the bridge" do
    # The reference transport validates the source window for exactly this
    # reason: without it, any frame able to postMessage into this window could
    # forge a JSON-RPC result or a ui/notifications/tool-input.
    expect(script).to include("if (event.source !== window.parent) return;")
  end

  it "exposes the handshake's failed state so callers need not guess from `available`" do
    # `available` is only "am I in a frame", which is true in hosts that do not
    # speak MCP Apps at all. A caller that must not act on a dead session reads
    # this instead.
    expect(script).to include("handshakeFailed: function () { return handshakeError !== null; }")
  end

  describe "handshake timeout" do
    it "emits a bounded wait on ui/initialize rather than an unbounded one" do
      expect(McpApps::Bridge::HANDSHAKE_TIMEOUT_MS).to eq(10_000)
      expect(script).to include("var HANDSHAKE_TIMEOUT_MS = 10000;")
      expect(script).to include("setTimeout(function () {")
    end

    it "emits a queue drain and a console.error on the timeout path" do
      expect(script).to include("queued.reject(error)")
      expect(script).to include("console.error(error.message)")
    end

    it "emits a console.error for an explicit rejection from the host too" do
      expect(script).to include("console.error('MCP Apps handshake failed:', error)")
    end

    it "emits the queue drain on BOTH failure paths, not just the timeout" do
      # Round 2 drained the queue when the handshake timed out but not when the
      # host answered ui/initialize with a JSON-RPC error. A request queued
      # before that error arrived then stayed pending forever with no
      # diagnostic — the same hang the timeout path exists to prevent.
      expect(script.scan("queue.splice(0).forEach(function (queued) { queued.reject(error); });").length)
        .to eq(2) # timeout + explicit host rejection
    end

    it "emits the terminal handshakeError check, so a call made after a failure rejects at once" do
      # Round 1 only rejected calls already queued at the moment the handshake
      # failed. A call made later would still queue behind a handshake that
      # will never complete and hang forever with no diagnostic — the very
      # symptom the timeout was meant to eliminate. `handshakeError` closes
      # that gap: request() consults it up front, before ever deciding whether
      # to send immediately or queue.
      expect(script).to include("var handshakeError = null;")
      expect(script).to include("if (handshakeError && method !== 'ui/initialize') {")
      expect(script).to include("return Promise.reject(handshakeError);")

      # Set on both failure paths, not just the timeout.
      expect(script.scan("handshakeError = error;").length).to eq(2) # timeout + explicit host rejection
    end
  end

  describe "ui/initialize protocol conformance" do
    # The one example here tied to something outside this repo. Per SEP-1865
    # (MCP Apps, protocol version 2026-01-26), the `ui/initialize` request
    # params are three REQUIRED fields:
    #
    #   params: { appInfo: Implementation,
    #             appCapabilities: McpUiAppCapabilities,
    #             protocolVersion: string }
    #
    # and the reference host registers that handler with schema validation
    # attached (a non-passthrough z.object with appInfo and protocolVersion
    # required). A request missing either one is answered with a JSON-RPC error
    # rather than a result, so connect() rejects, every queued call is drained
    # with that error, and the view renders its "could not reach the host"
    # state. Dropping a param therefore breaks the app against a conformant
    # host while every other example in this file stays green — which is what
    # happened before this example existed.
    let(:params_source) { script[/request\('ui\/initialize', \{(.*?)\}\)\.then/m, 1] }

    it "sends exactly the ratified required params" do
      expect(params_source).not_to be_nil

      # Keys of the params object itself each sit at the start of their own
      # line; nested keys (name/version, availableDisplayModes) never do.
      expect(params_source.scan(/^\s+(\w+):/).flatten)
        .to match_array(%w[appInfo appCapabilities protocolVersion])
    end

    it "sends the protocol version the module declares, not a placeholder" do
      expect(described_class::PROTOCOL_VERSION).to eq("2026-01-26")
      expect(script).to include("var PROTOCOL_VERSION = '2026-01-26';")
      expect(params_source).to include("protocolVersion: PROTOCOL_VERSION")
    end

    it "takes appInfo from the caller, keeping the bridge application-agnostic" do
      expect(script).to include("connect: function (appInfo)")
      expect(params_source).to include("appInfo: appInfo")
    end
  end
end
