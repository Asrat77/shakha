# frozen_string_literal: true

module Shakha
  class Engine < ::Rails::Engine
    isolate_namespace Shakha

    config.after_initialize do
      Shakha::ConfigValidator.validate!(Shakha.config)
    end

    routes do
      root to: "auth#new"

      get  ":provider/authorize" => "auth#authorize"
      get  ":provider/callback"  => "auth#callback"
      delete "sign_out"           => "auth#destroy"
      get  "error"                => "auth#error"

      get  "session"        => "session#show"
      get  "session/check"  => "session#check"
    end
  end
end