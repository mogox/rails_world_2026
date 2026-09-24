# frozen_string_literal: true

# Companion script for script/coatepec_benchmark.rb: the direct-Rails
# baseline for the rails_model MCP tool. Run via `bin/rails runner`, mirrors
# the shape of data rails_model returns (schema, associations, validators,
# enums) for the model named in COATEPEC_BENCH_MODEL.

klass = ENV.fetch("COATEPEC_BENCH_MODEL", "CoffeePlace").constantize
klass.columns_hash.each { |name, col| [name, col.type, col.null] }
klass.reflect_on_all_associations.map { |a| [a.name, a.macro] }
klass.validators.map { |v| [v.class.name, v.attributes] }
klass.defined_enums
nil
