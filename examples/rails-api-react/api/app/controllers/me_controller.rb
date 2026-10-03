class MeController < ApplicationController
  before_action :authenticate!

  def show
    render json: current_user.slice(:id, :email, :name, :picture, :provider)
  end
end
