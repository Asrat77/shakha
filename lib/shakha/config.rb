# frozen_string_literal: true

module Shakha
  class Config
    attr_accessor :app_origin,
                  :app_name,
                  :google_client_id,
                  :google_client_secret,
                  :github_client_id,
                  :github_client_secret,
                  :providers,
                  :session_lifetime,
                  :rate_limiting_enabled,
                  :allowed_redirect_origins,
                  :redirect_token_delivery

    def initialize
      @app_name = "Shakha"
      @session_lifetime = 30.days
      @rate_limiting_enabled = false
      @providers = [ :google ]
      @redirect_token_delivery = :exchange_code
    end
  end
end
