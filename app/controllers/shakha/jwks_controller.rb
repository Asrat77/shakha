# frozen_string_literal: true

module Shakha
  class JwksController < ApplicationController
    def show
      render json: Shakha::JwtHandler.jwks,
             content_type: "application/json"
    end
  end
end