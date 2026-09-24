require "rails_helper"
require_relative "../../mcp_server/server"
require "rackup"
require "socket"

RSpec.describe "MCP Client integration with real MCP Server", type: :request do
  let(:server_url) { "http://127.0.0.1:#{@actual_port}" }

  before(:all) do
    # Find a free port by binding to port 0
    socket = TCPServer.new("127.0.0.1", 0)
    @actual_port = socket.addr[1]
    socket.close

    # Start the MCP server in a thread
    @server_thread = Thread.new do
      begin
        server = McpServer.build
        Rackup::Handler.get("puma").run(
          McpServer.rack_app(server),
          Port: @actual_port,
          Host: "127.0.0.1",
          Silent: true,
          Threads: "1:1"
        )
      rescue => e
        # Log any errors but don't raise (thread will exit)
        puts "Server error: #{e.inspect}"
      end
    end

    # Give the server time to start
    sleep 2

    # Wait for the server to be ready by attempting a connection
    max_retries = 10
    retries = 0
    loop do
      begin
        socket = TCPSocket.new("127.0.0.1", @actual_port)
        socket.close
        break
      rescue Errno::ECONNREFUSED
        retries += 1
        if retries >= max_retries
          raise "Server failed to start after #{max_retries} attempts"
        end
        sleep 0.5
      end
    end
  end

  after(:all) do
    # Stop the server thread if it's still running
    @server_thread&.kill
    sleep 0.5
  end

  it "calls the real MCP server and returns the coffee place card HTML" do
    # Create a coffee place in the test database
    coffee_place = CoffeePlace.create!(name: "Integration Test Coffee", address: "123 Test Ave")

    # Create a real client pointing at the test server
    client = Mcp::Client.new(server_url: server_url)

    # Call the real client against the real server
    html = client.coffee_place_card(coffee_place.id)

    # Verify the response contains HTML and the coffee place's name
    expect(html).to include("<h2")
    expect(html).to include("Integration Test Coffee")
    expect(html).to include("</h2>")
  end

  it "calls set_favorite_drink on the real MCP server with explicit nulls to clear the drink" do
    coffee = Coffee.create!(name: "Pour Over")
    coffee_place = CoffeePlace.create!(name: "Integration Test Coffee", address: "123 Test Ave", favorite_drink: coffee)

    client = Mcp::Client.new(server_url: server_url)

    html = client.call_action("set_favorite_drink", { id: coffee_place.id, beverage_type: nil, beverage_id: nil })

    expect(html).to include("Integration Test Coffee")
    expect(coffee_place.reload.favorite_drink).to be_nil
  end
end
