#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmarks coatepec's MCP tools against calling Rails directly, so the
# comparison can be re-run the same way every time instead of by hand.
#
# Usage:
#   ruby script/coatepec_benchmark.rb [options]
#
#   --runs N              Number of timed runs per benchmark (default: 10)
#   --spec-path P         Spec file used for the rails_spec_run benchmark
#                         (default: spec/models/coffee_place_spec.rb)
#   --model NAME          Model class used for the rails_model benchmark
#                         (default: CoffeePlace)
#   --polymorphic-model NAME
#                         Model class used for the second rails_model benchmark,
#                         chosen to exercise a genuinely polymorphic association
#                         (default: Beverage, whose has_many :coffee_places, as:
#                         :favorite_drink is the has_many-side of CoffeePlace's
#                         polymorphic belongs_to)
#
# Each pair (MCP tool vs. its direct-Rails equivalent) is run the requested
# number of times, back to back, against the same warm coatepec worker used
# for the whole script. Prints avg/min/max wall-clock time per pair.
#
# Run with plain `ruby`, not `bundle exec`: coatepec and mcp are installed
# once outside this app's bundle (see README), so `bundle exec` would hide
# them behind this Gemfile's own load path instead of finding the system
# gems. The direct-Rails baselines spawned below (`bundle exec rspec`,
# `bin/rails ...`) still run inside this app's bundle themselves.

require "mcp/client"
require "json"
require "optparse"

ROOT = File.expand_path("..", __dir__)

options = {
  runs: 10,
  spec_path: "spec/models/coffee_place_spec.rb",
  model: "CoffeePlace",
  polymorphic_model: "Beverage",
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby script/coatepec_benchmark.rb [options]"
  opts.on("--runs N", Integer, "Number of runs per benchmark (default: 10)") { |v| options[:runs] = v }
  opts.on("--spec-path PATH", "Spec file for the rails_spec_run benchmark") { |v| options[:spec_path] = v }
  opts.on("--model NAME", "Model class for the rails_model benchmark") { |v| options[:model] = v }
  opts.on("--polymorphic-model NAME", "Model class for the polymorphic-association rails_model benchmark") do |v|
    options[:polymorphic_model] = v
  end
end.parse!

def time_it
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  yield
  Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
end

def run_direct(*cmd, env: {})
  time_it do
    ok = system(env, *cmd, out: File::NULL, err: File::NULL, chdir: ROOT)
    warn "  warning: #{cmd.join(" ")} exited non-zero" unless ok
  end
end

# Raises if the tool call failed at the JSON-RPC or tool level; otherwise
# returns the parsed {"ok" => ..., "data" => ..., "meta" => ...} payload
# every coatepec tool wraps its response in.
def call_tool!(client, name, arguments = nil)
  response = client.call_tool(name: name, arguments: arguments)
  result = response["result"] || {}
  text = result.dig("content", 0, "text")
  raise "#{name} returned no content: #{result.inspect}" unless text

  payload = JSON.parse(text)
  raise "#{name} failed: #{payload["error"]}" if result["isError"] || payload["ok"] == false

  payload
end

def stats(label, seconds)
  ms = seconds.map { |s| (s * 1000).round(1) }
  { label: label, avg: (ms.sum / ms.size).round(1), min: ms.min, max: ms.max }
end

def print_table(rows)
  label_width = rows.map { |r| r[:label].length }.max
  header = format("%-#{label_width}s  %10s  %10s  %10s", "benchmark", "avg (ms)", "min (ms)", "max (ms)")
  puts header
  puts "-" * header.length
  rows.each do |r|
    puts format("%-#{label_width}s  %10s  %10s  %10s", r[:label], r[:avg], r[:min], r[:max])
  end
end

puts "Booting coatepec MCP server (coatepec --root #{ROOT})..."
transport = MCP::Client::Stdio.new(
  command: "coatepec",
  args: ["--root", ROOT],
  env: { "OBJC_DISABLE_INITIALIZE_FORK_SAFETY" => "YES" },
)
client = MCP::Client.new(transport: transport)
client.connect(client_info: { name: "coatepec-benchmark", version: "1.0" })

warmup = call_tool!(client, "rails_runtime_status")
puts "Worker ready: #{warmup["data"].slice("ruby_version", "rails_version", "coatepec_version")}"
puts

results = []

puts "Benchmarking rails_spec_run vs `bundle exec rspec` (#{options[:runs]} runs each, #{options[:spec_path]})..."
mcp_times = Array.new(options[:runs]) { time_it { call_tool!(client, "rails_spec_run", { paths: [options[:spec_path]] }) } }
direct_times = Array.new(options[:runs]) { run_direct("bundle", "exec", "rspec", options[:spec_path]) }
results << stats("rails_spec_run (MCP)", mcp_times)
results << stats("bundle exec rspec (direct)", direct_times)

puts "Benchmarking rails_routes vs `bin/rails routes` (#{options[:runs]} runs each)..."
mcp_times = Array.new(options[:runs]) { time_it { call_tool!(client, "rails_routes") } }
direct_times = Array.new(options[:runs]) { run_direct("bin/rails", "routes") }
results << stats("rails_routes (MCP)", mcp_times)
results << stats("bin/rails routes (direct)", direct_times)

puts "Benchmarking rails_model vs `bin/rails runner` introspection (#{options[:runs]} runs each, #{options[:model]})..."
introspect_script = File.join(ROOT, "script", "coatepec_benchmark_introspect.rb")
mcp_times = Array.new(options[:runs]) { time_it { call_tool!(client, "rails_model", { name: options[:model] }) } }
direct_times = Array.new(options[:runs]) do
  run_direct("bin/rails", "runner", introspect_script, env: { "COATEPEC_BENCH_MODEL" => options[:model] })
end
results << stats("rails_model (MCP)", mcp_times)
results << stats("bin/rails runner introspect (direct)", direct_times)

puts "Benchmarking rails_model vs `bin/rails runner` introspection on a polymorphic association " \
     "(#{options[:runs]} runs each, #{options[:polymorphic_model]})..."
mcp_times = Array.new(options[:runs]) do
  time_it { call_tool!(client, "rails_model", { name: options[:polymorphic_model] }) }
end
direct_times = Array.new(options[:runs]) do
  run_direct("bin/rails", "runner", introspect_script, env: { "COATEPEC_BENCH_MODEL" => options[:polymorphic_model] })
end
results << stats("rails_model, polymorphic assoc (MCP)", mcp_times)
results << stats("bin/rails runner introspect, polymorphic assoc (direct)", direct_times)

client.transport.close

puts
print_table(results)
