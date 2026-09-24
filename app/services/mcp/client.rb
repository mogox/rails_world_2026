# frozen_string_literal: true

require "net/http"
require "base64"

module Mcp
  class Client
    class ConnectionError < StandardError; end
    class ToolError < StandardError; end

    def initialize(server_url: ENV.fetch("MCP_SERVER_URL", "http://localhost:3001"), mcp_client: nil)
      @server_url = server_url
      @injected_client = mcp_client
    end

    def coffee_place_card(id)
      with_connected_client do |client|
        envelope = client.call_tool(name: "get_coffee_place_card", arguments: { id: id })
        result = envelope["result"] || {}

        raise ToolError, error_text(result) if result["isError"]

        html(result)
      end
    end

    def call_action(tool_name, params)
      with_connected_client do |client|
        write_envelope = client.call_tool(name: tool_name, arguments: params)
        write_result = write_envelope["result"] || {}

        raise ToolError, error_text(write_result) if write_result["isError"]

        card_envelope = client.call_tool(name: "get_coffee_place_card", arguments: { id: params[:id] })
        card_result = card_envelope["result"] || {}

        raise ToolError, error_text(card_result) if card_result["isError"]

        html(card_result)
      end
    end

    private

    def with_connected_client
      client = mcp_client
      client.connect(client_info: { name: "coffee_spots", version: "1.0" })
      yield client
    rescue MCP::Client::ServerError => e
      raise ToolError, e.message
    rescue MCP::Client::RequestHandlerError, Faraday::Error, Errno::ECONNREFUSED, SocketError => e
      raise ConnectionError, "Could not reach the MCP server at #{@server_url}: #{e.message}"
    ensure
      begin
        client.transport.close if client.transport.respond_to?(:connected?) && client.transport.connected?
      rescue StandardError => e
        Rails.logger.debug("MCP client close failed: #{e.class}: #{e.message}")
      end
    end

    def mcp_client
      @injected_client || MCP::Client.new(transport: MCP::Client::HTTP.new(url: @server_url))
    end

    def html(result)
      resource_item = Array(result["content"]).find { |item| item["type"] == "resource" }
      raise ToolError, "No UI resource returned for coffee place card" unless resource_item

      resource = resource_item["resource"]
      if resource["blob"]
        Base64.decode64(resource["blob"])
      elsif resource["text"]
        resource["text"]
      else
        raise ToolError, "Coffee place card resource has neither text nor blob content"
      end
    end

    def error_text(result)
      text_item = Array(result["content"]).find { |item| item["type"] == "text" }
      text_item ? text_item["text"] : "Unknown MCP tool error"
    end
  end
end
