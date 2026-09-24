require 'rails_helper'

RSpec.describe "Adding a coffee place", type: :feature do
  it "lets a user add a place and see it in the list" do
    visit root_path
    click_link "Add a coffee place"

    fill_in "Name", with: "Ritual Coffee"
    fill_in "Address", with: "1026 Valencia St"
    select "5", from: "Rating"
    click_button "Add place"

    expect(page).to have_current_path(coffee_places_path)
    expect(page).to have_content("Ritual Coffee")
    expect(page).to have_content("1026 Valencia St")
  end

  it "shows validation errors when required fields are missing" do
    visit new_coffee_place_path

    click_button "Add place"

    expect(page).to have_content("Name can't be blank")
    expect(page).to have_content("Address can't be blank")
  end

  it "lets a user pick a favorite drink" do
    Coffee.create!(name: "Pour Over")

    visit root_path
    click_link "Add a coffee place"

    fill_in "Name", with: "Ritual Coffee"
    fill_in "Address", with: "1026 Valencia St"
    select "Pour Over", from: "Favorite drink"
    click_button "Add place"

    expect(page).to have_content("Favorite drink: Pour Over")
  end

  it "links the site title back to the home page" do
    visit new_coffee_place_path

    click_link "Coffee Spots"

    expect(page).to have_current_path(root_path)
  end
end
