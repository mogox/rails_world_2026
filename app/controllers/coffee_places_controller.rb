class CoffeePlacesController < ApplicationController
  ALLOWED_MCP_ACTIONS = %w[rate_coffee_place set_favorite_drink].freeze

  def index
    @coffee_places = CoffeePlace.preload(:favorite_drink).order(created_at: :desc)
  end

  def show
    @coffee_place = CoffeePlace.find(params[:id])

    begin
      @card_html = Mcp::Client.new.coffee_place_card(@coffee_place.id)
    rescue Mcp::Client::ConnectionError, Mcp::Client::ToolError => e
      Rails.logger.warn("MCP card unavailable for coffee place #{@coffee_place.id}: #{e.class}: #{e.message}")
      @mcp_unavailable = true
    end
  end

  def mcp_action
    tool_name = params[:tool_name].to_s

    unless ALLOWED_MCP_ACTIONS.include?(tool_name)
      return render json: { error: "Unknown action" }, status: :unprocessable_content
    end

    coffee_place = CoffeePlace.find(params[:id])
    action_params = params[:params].is_a?(ActionController::Parameters) ? params[:params].to_unsafe_h.symbolize_keys : {}

    html = Mcp::Client.new.call_action(tool_name, action_params.merge(id: coffee_place.id))
    render json: { html: html }
  rescue Mcp::Client::ConnectionError, Mcp::Client::ToolError => e
    Rails.logger.warn("MCP action #{tool_name} failed for coffee place #{params[:id]}: #{e.class}: #{e.message}")
    render json: { error: e.message }, status: :unprocessable_content
  end

  def new
    @coffee_place = CoffeePlace.new
  end

  def create
    @coffee_place = CoffeePlace.new(coffee_place_params.except(:favorite_drink))
    assign_favorite_drink

    if @coffee_place.save
      redirect_to coffee_places_path, notice: "Coffee place added."
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  def coffee_place_params
    params.expect(coffee_place: [ :name, :address, :rating, :favorite_drink ])
  end

  # The form posts favorite_drink as "Coffee-3"/"Tea-1"/"" (see new.html.erb) rather than
  # separate id/type fields, since a plain <select> can't submit two params from one choice
  # without JS. Split it apart, and only ever assign a real, allowlisted record through the
  # association writer — never write favorite_drink_type/_id directly from unvalidated input,
  # since that lets an arbitrary POST persist a type string that later 500s on constantize.
  def assign_favorite_drink
    type, id = coffee_place_params[:favorite_drink].to_s.split("-", 2)
    return unless %w[Coffee Tea].include?(type) && id.present?

    @coffee_place.favorite_drink = type.constantize.find_by(id: id)
  end
end
