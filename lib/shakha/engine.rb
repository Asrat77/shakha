# frozen_string_literal: true

module Shakha
  class Engine < ::Rails::Engine
    isolate_namespace Shakha

    config.app_middleware.use Shakha::Middleware

    # Engine routes - these should be relative paths
    routes do
      root to: "auth#new"

      get "authorize" => "auth#authorize"
      get "callback" => "auth#callback"
      post "token" => "auth#token"
      get "error" => "auth#error"

      get "session" => "session#show"
      post "session/check" => "session#check"
      delete "session" => "session#destroy"

      get ".well-known/jwks.json" => "jwks#show"
      get ".well-known/openid-configuration" => "openid#configuration"
    end
  end
end