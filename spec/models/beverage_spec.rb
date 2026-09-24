require 'rails_helper'

RSpec.describe Beverage, type: :model do
  it "is invalid without a name" do
    beverage = Coffee.new(name: nil)

    expect(beverage).not_to be_valid
  end

  it "is valid with a name" do
    beverage = Coffee.new(name: "Pour Over")

    expect(beverage).to be_valid
  end

  it "finds coffee places assigned through the association" do
    coffee = Coffee.create!(name: "Pour Over")
    place = CoffeePlace.create!(name: "Blue Bottle", address: "123 Main St", favorite_drink: coffee)

    expect(coffee.coffee_places).to include(place)
    expect(place.reload.favorite_drink_type).to eq("Coffee")
  end
end

RSpec.describe Coffee, type: :model do
  it "is an STI subclass of Beverage" do
    expect(Coffee.new).to be_a(Beverage)
  end
end

RSpec.describe Tea, type: :model do
  it "is an STI subclass of Beverage" do
    expect(Tea.new).to be_a(Beverage)
  end
end
