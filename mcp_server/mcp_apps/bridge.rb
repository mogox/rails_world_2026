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

    # Bounded wait for the one-time ui/initialize handshake only. This is not the
    # request queue/retry/timeout machinery the project's global constraints
    # forbid — there is still no timeout and no retry on any individual
    # `tools/call` or `resources/read`, and only one handshake ever happens. It
    # exists so a host that never replies (or whose reply is dropped) produces a
    # visible, logged error instead of every later call hanging silently forever.
    HANDSHAKE_TIMEOUT_MS = 10_000

    module_function

    def script
      <<~JS.chomp
        (function () {
          var HANDSHAKE_TIMEOUT_MS = #{HANDSHAKE_TIMEOUT_MS};
          var PROTOCOL_VERSION = '#{PROTOCOL_VERSION}';
          var nextId = 1;
          var pending = {};
          var queue = [];
          var ready = false;
          // Terminal state once the handshake has failed (timeout or explicit
          // host rejection), so a call made AFTER that point — not just one
          // already queued when it happened — rejects immediately instead of
          // queuing behind a handshake that is never coming back.
          var handshakeError = null;
          var toolInputHandlers = [];
          var available = window.parent !== window;

          function post(message) {
            window.parent.postMessage(message, '*');
          }

          function request(method, params) {
            if (handshakeError && method !== 'ui/initialize') {
              return Promise.reject(handshakeError);
            }

            return new Promise(function (resolve, reject) {
              var id = nextId++;
              var send = function () {
                pending[id] = { resolve: resolve, reject: reject };
                post({ jsonrpc: '2.0', id: id, method: method, params: params });
              };
              if (ready || method === 'ui/initialize') { send(); } else { queue.push({ send: send, reject: reject }); }
            });
          }

          function notify(method, params) {
            post({ jsonrpc: '2.0', method: method, params: params || {} });
          }

          window.addEventListener('message', function (event) {
            // The only peer this view ever speaks to is the host frame that
            // embeds it. Without this check any frame able to reach this window
            // could forge a JSON-RPC result or a ui/notifications/tool-input.
            if (event.source !== window.parent) return;

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

            // Whether the one-time handshake has already failed (timed out or
            // been rejected by the host). A view embedded in a frame that does
            // not speak MCP Apps at all is `available` but will never be
            // connected, so callers that must not act on a dead session read
            // this rather than `available`.
            handshakeFailed: function () { return handshakeError !== null; },

            connect: function (appInfo) {
              if (!available) return Promise.reject(new Error('not in a frame'));

              return new Promise(function (resolve, reject) {
                var settled = false;

                var timer = setTimeout(function () {
                  if (settled) return;
                  settled = true;
                  var error = new Error('MCP Apps handshake timed out after ' + HANDSHAKE_TIMEOUT_MS + 'ms');
                  console.error(error.message);
                  handshakeError = error;
                  // Nothing is coming: reject every call left waiting on the
                  // handshake rather than leaving it pending forever.
                  queue.splice(0).forEach(function (queued) { queued.reject(error); });
                  reject(error);
                }, HANDSHAKE_TIMEOUT_MS);

                // All three params are REQUIRED by the ratified ui/initialize
                // request schema, and the reference host validates them: a
                // request missing appInfo or protocolVersion comes back as a
                // JSON-RPC error instead of a result. `appInfo` identifies the
                // view, so it comes from the caller — this file stays free of
                // any application vocabulary.
                request('ui/initialize', {
                  appInfo: appInfo || { name: 'mcp-app-view', version: '0.0.0' },
                  appCapabilities: { availableDisplayModes: ['inline', 'fullscreen'] },
                  protocolVersion: PROTOCOL_VERSION
                }).then(function (result) {
                  if (settled) return;
                  settled = true;
                  clearTimeout(timer);
                  notify('ui/notifications/initialized');
                  ready = true;
                  queue.splice(0).forEach(function (queued) { queued.send(); });
                  resolve(result);
                }, function (error) {
                  if (settled) return;
                  settled = true;
                  clearTimeout(timer);
                  console.error('MCP Apps handshake failed:', error);
                  handshakeError = error;
                  // Same as the timeout path: the handshake is never completing,
                  // so nothing queued behind it can ever be sent.
                  queue.splice(0).forEach(function (queued) { queued.reject(error); });
                  reject(error);
                });
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
