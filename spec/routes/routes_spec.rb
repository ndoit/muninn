require 'rails_helper'

RSpec.describe "routing to datasets", :type => :routing do
  it "goes to dataset#index with a blank url '/datasets/'" do
    expect(:get => "/datasets/").to route_to(
      :controller => "datasets",
      :action => "index"
      )
  end

  it "goes to the show method from '/datasets/id/example_dataset'" do
    expect(:get => "/datasets/example_dataset").to route_to(
      :controller => "datasets",
      :action => "show",
      :unique_property => "example_dataset"
      )
  end
  it "goes to the show method from '/datasets/id/:id'" do
    expect(:get => "/datasets/1").to route_to(
      :controller => "datasets",
      :action => "show",
      :unique_property => "1"
      )
  end

end

