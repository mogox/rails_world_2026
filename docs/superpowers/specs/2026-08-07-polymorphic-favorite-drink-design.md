# Polymorphic favorite drink for coffee places

## Purpose

Add a `favorite_drink` to `CoffeePlace`, polymorphic across two beverage
types (`Coffee`, `Tea`) that share a common `Beverage` base via single-table
inheritance. Beyond the product value, this exercises coatepec's
`rails_model` tool against a genuinely polymorphic association — the exact
shape of reflection (`has_many ... as: :favorite_drink` on an STI base
class, and the `belongs_to ..., polymorphic: true` on the other side) that
coatepec 0.5.1 specifically fixed crashes for.

## Data model

- `beverages` table (STI): `type` (discriminator: `"Coffee"`/`"Tea"`),
  `name`, `description`, `caffeine_mg`, `roast_level` (nullable, Coffee-only),
  `steep_time_minutes` (nullable, Tea-only).
- `Beverage < ApplicationRecord`: `validates :name, presence: true`,
  `has_many :coffee_places, as: :favorite_drink`.
- `Coffee < Beverage`, `Tea < Beverage`: no additional behavior for now,
  just the STI split.
- `coffee_places` table gains `favorite_drink_id` + `favorite_drink_type`
  (the polymorphic pair; `favorite_drink_type` holds the STI subclass name,
  `"Coffee"` or `"Tea"`).
- `CoffeePlace belongs_to :favorite_drink, polymorphic: true, optional: true`
  (optional: existing places have no drink assigned yet).

## Seed data

`db/seeds.rb` creates a couple of `Coffee` and `Tea` records so the UI has
real options to select from.

## UI

- New/edit coffee place form: a `favorite_drink` select, grouped by type
  (`grouped_options_for_select` over Coffee then Tea beverages).
- Index card: show the favorite drink's name, if set.

## Tests

- Model specs for `Beverage`, `Coffee`, `Tea` (name validation, the
  polymorphic `has_many`).
- Extend the `CoffeePlace` spec for the new association.
- Update `spec/features/adding_a_coffee_place_spec.rb` if the form change
  affects it.

## Out of scope

- No drink CRUD UI (beverages are seeded, not user-managed).
- No caffeine/roast/steep-time display in the UI — those columns exist to
  give `rails_model` non-trivial column data to introspect, not for product
  use yet.
