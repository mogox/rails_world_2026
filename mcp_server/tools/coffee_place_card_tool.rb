# frozen_string_literal: true

require_relative "../mcp_apps/bridge"

class CoffeePlaceCardTool < MCP::Tool
  tool_name "get_coffee_place_card"
  title "Get Coffee Place Card"
  description "Returns an MCP-UI HTML card for a single coffee place"
  input_schema(
    properties: { id: { type: "integer", description: "The coffee place's id" } },
    required: ["id"],
  )

  # Every `ui://` URI this app serves hangs off one prefix: the static template,
  # the per-place cards, and the `{id}` resource template registered in
  # `McpServer`. Spelled once so the Ruby sites and the two emitted JavaScript
  # documents cannot drift apart.
  CARD_URI_PREFIX = "ui://coffee-place-card/"

  # The static MCP Apps UI template this tool renders through. Per the ratified
  # spec the linked `resourceUri` MUST be a concrete, pre-declared `ui://` URI —
  # it is NOT an RFC 6570 template, and per-call data (here, which place) flows
  # through `ui/notifications/tool-input` instead. The per-place card itself is
  # served by the `ui://coffee-place-card/{id}` resource template, which the
  # shell reads once it knows the id.
  TEMPLATE_URI = "#{CARD_URI_PREFIX}template"

  # Sent as the ratified `ui/initialize` `appInfo` param by both views (the
  # shell and the card it installs) — the bridge itself stays application
  # -agnostic and takes this from its caller.
  APP_INFO = { name: "coffee-place-card", version: "1.0.0" }.freeze

  meta MCP::Apps.tool_meta(resource_uri: TEMPLATE_URI)

  BLUE_BOTTLE_LOGO = <<~SVG.strip
    <svg viewBox="0 0 48 48" width="48" height="48" xmlns="http://www.w3.org/2000/svg">
      <rect x="10" y="10" width="22" height="4" rx="2" fill="#2563eb"/>
      <rect x="10" y="14" width="22" height="20" rx="3" fill="#2563eb"/>
      <path d="M32 18h4a4 4 0 0 1 0 8h-4" fill="none" stroke="#2563eb" stroke-width="3"/>
    </svg>
  SVG

  RITUAL_LOGO = <<~SVG.strip
    <svg viewBox="0 0 48 48" width="48" height="48" xmlns="http://www.w3.org/2000/svg">
      <rect x="12" y="10" width="24" height="6" rx="2" fill="#16a34a"/>
      <path d="M14 16h20l-3 20a2 2 0 0 1-2 2H19a2 2 0 0 1-2-2z" fill="#16a34a"/>
    </svg>
  SVG

  SAINT_FRANK_LOGO = <<~SVG.strip
    <svg viewBox="0 0 48 48" width="48" height="48" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="24" cy="24" rx="14" ry="20" fill="#c2410c" transform="rotate(20 24 24)"/>
      <path d="M24 6c-4 8-4 28 0 36" fill="none" stroke="#7c2d12" stroke-width="2" transform="rotate(20 24 24)"/>
    </svg>
  SVG

  SIGHTGLASS_LOGO = <<~SVG.strip
    <svg viewBox="0 0 48 48" width="48" height="48" xmlns="http://www.w3.org/2000/svg">
      <path d="M14 12h20l-6 18h-8z" fill="#0d9488"/>
      <rect x="18" y="30" width="12" height="10" rx="2" fill="none" stroke="#0d9488" stroke-width="3"/>
    </svg>
  SVG

  PHILZ_LOGO = <<~SVG.strip
    <svg viewBox="0 0 48 48" width="48" height="48" xmlns="http://www.w3.org/2000/svg">
      <path d="M12 22c0-6 5-10 12-10s12 4 12 10v6c0 4-3 6-6 6H18c-3 0-6-2-6-6z" fill="#d97706"/>
      <path d="M34 19c5-3 9 0 9 4s-4 6-8 5" fill="none" stroke="#d97706" stroke-width="3" stroke-linecap="round"/>
      <circle cx="24" cy="9" r="2.5" fill="#d97706"/>
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
    "Ritual Coffee Roasters" => RITUAL_LOGO,
    "Saint Frank Coffee" => SAINT_FRANK_LOGO,
    "Sightglass Coffee" => SIGHTGLASS_LOGO,
    "Philz Coffee" => PHILZ_LOGO,
  }.freeze

  DEFAULT_ACCENT = "#6b7280"

  ACCENTS = {
    "Blue Bottle" => "#2563eb",
    "Ritual Coffee Roasters" => "#16a34a",
    "Saint Frank Coffee" => "#c2410c",
    "Sightglass Coffee" => "#0d9488",
    "Philz Coffee" => "#d97706",
  }.freeze

  # Tool-specific labels shown in the "<label> updated via MCP ✓" toast, so the
  # confirmation names the actual mechanism that just ran rather than a generic
  # "Saved" — the toast is meant to reinforce the round trip for an audience.
  TOOL_LABELS = {
    "rate_coffee_place" => "Rating",
    "set_favorite_drink" => "Favorite drink",
  }.freeze

  class << self
    def call(id:)
      place = CoffeePlace.find_by(id: id)

      return not_found_response(id) unless place

      ui_resource = McpUiServer.create_ui_resource(
        uri: "#{CARD_URI_PREFIX}#{place.id}",
        content: { type: :raw_html, htmlString: card_html(place) },
        encoding: :text,
      )

      MCP::Tool::Response.new([ui_resource])
    end

    # Full card document for a place id, or nil when it does not exist. Shared by
    # the tool response path (Rails) and the MCP Apps resource-template path, so
    # there is exactly one card-rendering implementation.
    def card_html_for(id)
      place = CoffeePlace.find_by(id: id)
      place && card_html(place)
    end

    # The static MCP Apps UI template. The host loads this once per tool call,
    # completes the handshake with it, then reports the tool's arguments via
    # `ui/notifications/tool-input`. Only then does the shell know WHICH place to
    # show, so it reads `ui://coffee-place-card/<id>` and installs that
    # server-rendered document — no card markup is duplicated in JavaScript.
    #
    # `document.write` rather than `innerHTML`: the fetched card carries its own
    # <script> (the bridge plus the card behavior), and script elements inserted
    # via innerHTML never execute.
    #
    # A loading timeout backstops the whole sequence: if the handshake never
    # settles, or it settles but the host never sends tool-input, the shell
    # reports a visible, logged error instead of sitting on "Loading…" forever.
    # A non-numeric id (e.g. the template resource's own id, "template") is
    # rejected the same way a missing id is.
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
              var cardInstalled = false;
              var errorShown = false;

              function installCard(html) {
                cardInstalled = true;
                clearTimeout(loadingTimer);
                document.open();
                document.write(html);
                document.close();
              }

              function showShellError(message) {
                errorShown = true;
                clearTimeout(loadingTimer);
                var shell = document.getElementById('card-shell');
                if (shell) shell.textContent = message;
              }

              // Bounded wait for the whole "become a working card" sequence: the
              // handshake completing AND the host then sending
              // ui/notifications/tool-input. Not a retry and not a per-call
              // timeout of its own — one guard that turns silence (a host that
              // never sends tool-input, even after a successful handshake) into
              // a visible, logged error instead of "Loading…" stuck forever.
              var loadingTimer = setTimeout(function () {
                if (cardInstalled || errorShown) return;
                var message = 'Timed out waiting for the coffee place to load.';
                console.error('MCP Apps shell: ' + message);
                showShellError(message);
              }, #{McpApps::Bridge::HANDSHAKE_TIMEOUT_MS});

              window.mcpApps.onToolInput(function (args) {
                if (!args || args.id === undefined || args.id === null || !/^\\d+$/.test(String(args.id))) {
                  showShellError('No coffee place id was provided.');
                  return;
                }

                window.mcpApps.readResource('#{CARD_URI_PREFIX}' + args.id).then(function (result) {
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

              window.mcpApps.connect(#{APP_INFO.to_json}).catch(function (error) {
                showShellError('Could not reach the host: ' + (error.message || 'unknown error'));
              });
            </script>
          </body>
        </html>
      HTML
    end

    def not_found_html(id)
      "<!doctype html><html><body><p>No coffee place found with id #{ERB::Util.html_escape(id.to_s)}</p></body></html>"
    end

    private

    def not_found_response(id)
      MCP::Tool::Response.new([{ type: "text", text: "No coffee place found with id #{id}" }], error: true)
    end

    def accent_rgb(hex)
      hex = hex.delete("#")
      [hex[0..1], hex[2..3], hex[4..5]].map { |part| part.to_i(16) }.join(", ")
    end

    def rating_stars_html(place)
      (1..5).map do |n|
        glyph = place.rating && n <= place.rating ? "★" : "☆"
        "<button type=\"button\" class=\"mcp-star\" onclick=\"sendAction('rate_coffee_place', {id: #{place.id}, rating: #{n}})\">#{glyph}</button>"
      end.join
    end

    def celebration_rating_html
      (0...5).map do |n|
        "<span class=\"celebration-rating-star\" style=\"animation-delay: #{(n * 0.15).round(2)}s;\">★</span>"
      end.join
    end

    def favorite_drink_select_html(place)
      selected_value = place.favorite_drink ? "#{place.favorite_drink_type}-#{place.favorite_drink_id}" : ""

      options = ["<option value=\"\"#{selected_value.empty? ? " selected" : ""}>— none —</option>"]

      { "Coffee" => Coffee.order(:name), "Tea" => Tea.order(:name) }.each do |type, beverages|
        beverages.each do |beverage|
          value = "#{type}-#{beverage.id}"
          selected_attr = value == selected_value ? " selected" : ""
          options << "<option value=\"#{value}\"#{selected_attr}>#{ERB::Util.html_escape(beverage.name)}</option>"
        end
      end

      <<~HTML.strip
        <select class="mcp-select" onchange="var parts = this.value.split('-'); sendAction('set_favorite_drink', {id: #{place.id}, beverage_type: parts[0] || null, beverage_id: parts[1] ? Number(parts[1]) : null})">
          #{options.join("\n          ")}
        </select>
      HTML
    end

    def card_styles_css(place)
      accent = ACCENTS.fetch(place.name, DEFAULT_ACCENT)
      accent_rgb_value = accent_rgb(accent)

      <<~CSS.chomp
        * { box-sizing: border-box; }

        :root {
          --accent: #{accent};
          --accent-rgb: #{accent_rgb_value};
        }

        .mcp-star {
          all: unset;
          cursor: pointer;
          font-size: 1.5rem;
          line-height: 1;
          transition: transform 0.15s ease, color 0.15s ease;
        }

        .mcp-star:hover {
          transform: scale(1.2);
          color: var(--accent);
        }

        .mcp-select {
          appearance: none;
          -webkit-appearance: none;
          background-color: #fff;
          background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 20 20' fill='%236b7280'%3E%3Cpath d='M5.25 7.5L10 12.25L14.75 7.5H5.25Z'/%3E%3C/svg%3E");
          background-repeat: no-repeat;
          background-position: right 0.5rem center;
          background-size: 0.9em;
          border: 1px solid #d1d5db;
          border-radius: 6px;
          padding: 0.35rem 1.75rem 0.35rem 0.6rem;
          font-size: 0.9rem;
          color: #111827;
          cursor: pointer;
          transition: border-color 0.15s ease, box-shadow 0.15s ease;
        }

        .mcp-select:hover {
          border-color: var(--accent);
        }

        .mcp-select:focus {
          outline: none;
          border-color: var(--accent);
          box-shadow: 0 0 0 3px rgba(var(--accent-rgb), 0.25);
        }

        .celebration {
          display: none;
          position: fixed;
          inset: 0;
          background: radial-gradient(ellipse at 50% 30%, #0b1029 0%, #000814 70%);
          overflow: hidden;
          cursor: pointer;
          z-index: 9999;
        }

        .celebration-star {
          position: absolute;
          width: 2px;
          height: 2px;
          background: #fff;
          border-radius: 50%;
          animation: twinkle 1.8s ease-in-out infinite;
        }

        @keyframes twinkle {
          0%, 100% { opacity: 0.2; transform: scale(1); }
          50% { opacity: 1; transform: scale(1.6); }
        }

        .celebration-comet {
          position: absolute;
          top: 15%;
          left: -10%;
          width: 3px;
          height: 3px;
          background: #fff;
          border-radius: 50%;
          box-shadow: 0 0 6px 2px rgba(255, 255, 255, 0.8);
          animation: comet-fly 3s ease-in infinite;
        }

        .celebration-comet::before {
          content: "";
          position: absolute;
          top: 50%;
          right: 100%;
          width: 80px;
          height: 1px;
          background: linear-gradient(to left, rgba(255, 255, 255, 0.8), transparent);
          transform: translateY(-50%);
        }

        @keyframes comet-fly {
          0% { transform: translate(0, 0); opacity: 0; }
          10% { opacity: 1; }
          90% { opacity: 1; }
          100% { transform: translate(140vw, 60vh); opacity: 0; }
        }

        .celebration-header {
          position: relative;
          z-index: 1;
          display: flex;
          align-items: center;
          gap: 0.5rem;
          padding: 1.25rem;
          color: #fff;
        }

        .celebration-rating {
          position: relative;
          z-index: 1;
          text-align: center;
          padding: 0.5rem 1rem 1rem;
          font-size: 3rem;
          line-height: 1;
          letter-spacing: 0.1em;
          color: #fbbf24;
        }

        .celebration-rating-star {
          display: inline-block;
          animation: celebration-star-blink 1.2s ease-in-out infinite;
        }

        @keyframes celebration-star-blink {
          0%, 100% { opacity: 0.3; transform: scale(0.9); }
          50% { opacity: 1; transform: scale(1.15); }
        }

        .celebration-logo {
          filter: brightness(0) invert(1);
        }

        .celebration-name {
          font-size: 1.1rem;
          font-weight: bold;
        }
      CSS
    end

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

        function showToast(message) {
          var toast = document.getElementById('toast');
          if (!toast) return;
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

        // Never rejects. Once the tool call has committed, a refresh problem must not be
        // reported as a failed save — it resolves false instead, and the caller says so.
        function refreshCard() {
          return window.mcpApps.readResource('#{CARD_URI_PREFIX}' + PLACE_ID).then(function (result) {
            var entry = (result && result.contents && result.contents[0]) || {};
            if (!entry.text) return false;
            applyCard(entry.text);
            return true;
          }).catch(function () {
            return false;
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
          //
          // Gated on the handshake, NOT on `available`: under Rails this card
          // runs in a sandboxed srcdoc iframe, so `available` (window.parent !==
          // window) is always true, yet Rails never answers ui/initialize. Once
          // the handshake has failed there is no session to call into, and
          // issuing the call anyway would reject and flash "Save failed" over a
          // save that in fact succeeded. Skipping is silent on purpose: Rails'
          // own tool-result reply reports the real outcome, and a genuine MCP
          // Apps host has already surfaced the handshake failure through
          // console.error and the shell's visible error.
          if (window.mcpApps && window.mcpApps.available && !window.mcpApps.handshakeFailed()) {
            // Two-argument then(): the rejection handler is bound to callTool alone,
            // so nothing after the write commits can report the save as failed.
            window.mcpApps.callTool(toolName, params).then(
              function () {
                refreshCard().then(function (refreshed) {
                  handleActionSuccess(toolName, params);
                  if (!refreshed) showToast('Saved — reopen the card to see the update.');
                  hideToastSoon();
                });
              },
              function (error) {
                showToast('Save failed: ' + (error.message || 'unknown error'));
                hideToastSoon();
              }
            );
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
          // A non-MCP-Apps host (Rails) never replies to ui/initialize, so this
          // fires only after the bridge's own handshake timeout — or for a
          // malformed reply from a real MCP Apps host. Logged for diagnostics;
          // non-fatal either way, since the Rails action path never depends on
          // this handshake.
          window.mcpApps.connect(#{APP_INFO.to_json}).catch(function (error) { console.error('MCP Apps handshake failed:', error); });
        }
      JS
    end

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
  end
end
