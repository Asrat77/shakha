# frozen_string_literal: true

module Shakha
  class Engine < ::Rails::Engine
    isolate_namespace Shakha

    config.after_initialize do
      Shakha::ConfigValidator.validate!(Shakha.config)
    end

    routes do
      root to: "auth#new"

      # Static routes MUST come before dynamic :provider routes
      get  "session"          => "session#show"
      get  "session/check"    => "session#check"
      post "session/exchange" => "session#exchange"
      delete "sign_out"       => "auth#destroy"
      get "error"             => "auth#error"

      # Dynamic provider routes
      get ":provider"          => "auth#authorize", as: :authorize
      get ":provider/callback" => "auth#callback",  as: :callback
    end
  end
end
