require 'rails_helper'

RSpec.describe CoffeePlace, type: :model do
  it "is valid with a name and address" do
    place = CoffeePlace.new(name: "Blue Bottle", address: "123 Main St")

    expect(place).to be_valid
  end

  it "is invalid without a name" do
    place = CoffeePlace.new(name: nil, address: "123 Main St")

    expect(place).not_to be_valid
  end

  it "is invalid without an address" do
    place = CoffeePlace.new(name: "Blue Bottle", address: nil)

    expect(place).not_to be_valid
  end

  it "is valid without a rating" do
    place = CoffeePlace.new(name: "Blue Bottle", address: "123 Main St", rating: nil)

    expect(place).to be_valid
  end

  it "is valid with a rating between 1 and 5" do
    place = CoffeePlace.new(name: "Blue Bottle", address: "123 Main St", rating: 5)

    expect(place).to be_valid
  end

  it "is invalid with a rating above 5" do
    place = CoffeePlace.new(name: "Blue Bottle", address: "123 Main St", rating: 6)

    expect(place).not_to be_valid
  end

  it "is invalid with a rating below 1" do
    place = CoffeePlace.new(name: "Blue Bottle", address: "123 Main St", rating: 0)

    expect(place).not_to be_valid
  end

  it "is valid without a favorite drink" do
    place = CoffeePlace.new(name: "Blue Bottle", address: "123 Main St", favorite_drink: nil)

    expect(place).to be_valid
  end

  it "can have a Coffee as its favorite drink" do
    coffee = Coffee.create!(name: "Pour Over")
    place = CoffeePlace.new(name: "Blue Bottle", address: "123 Main St", favorite_drink: coffee)

    expect(place).to be_valid
    expect(place.favorite_drink).to eq(coffee)
  end

  it "can have a Tea as its favorite drink" do
    tea = Tea.create!(name: "Sencha")
    place = CoffeePlace.new(name: "Blue Bottle", address: "123 Main St", favorite_drink: tea)

    expect(place).to be_valid
    expect(place.favorite_drink).to eq(tea)
  end
end
