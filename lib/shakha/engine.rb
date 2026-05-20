# frozen_string_literal: true

module Shakha
  class Engine < ::Rails::Engine
    isolate_namespace Shakha

    initializer "shakha.add_middleware" do |app|
      app.middleware.insert_before ActionDispatch::HostAuthorization, ActionDispatch::Cookies
      app.middleware.insert_before ActionDispatch::HostAuthorization, ActionDispatch::Session::CookieStore, key: '_shakha_session'
    end

    config.after_initialize do
      Shakha::ConfigValidator.validate!(Shakha.config)
    end

    routes do
      root to: "auth#new"

      # Static routes MUST come before dynamic :provider routes
      get "session"        => "session#show"
      get "session/check"  => "session#check"
      delete "sign_out"    => "auth#destroy"
      get "error"          => "auth#error"

      # Dynamic provider routes
      get ":provider"          => "auth#authorize"
      get ":provider/callback" => "auth#callback"
    end
  end
end