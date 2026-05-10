# frozen_string_literal: true

require "ostruct"

module Shakha
  class Engine < ::Rails::Engine
    isolate_namespace Shakha

    config.app_middleware.use Shakha::Middleware

    config.after_initialize do
      if Shakha.config.app_origin.blank?
        raise ConfigurationError, "Shakha.app_origin must be set"
      end
    end

    class EngineRouter
      def self.draw
        Drawer.new
      end

      class Drawer
        def initialize
          @routes = []
        end

        def resources(*args, &block)
          resource_options = args.last.is_a?(Hash) ? args.pop : {}
          resource_name = args.first

          @routes << { type: :resources, name: resource_name, options: resource_options, block: block }
        end

        def resource(*args, &block)
          resource_options = args.last.is_a?(Hash) ? args.pop : {}
          resource_name = args.first

          @routes << { type: :resource, name: resource_name, options: resource_options, block: block }
        end

        def get(path, to:, as: nil)
          @routes << { type: :get, path: path, to: to, as: as }
        end

        def post(path, to:, as: nil)
          @routes << { type: :post, path: path, to: to, as: as }
        end

        def match(path, to:, via:, as: nil)
          @routes << { type: :match, path: path, to: to, via: via, as: as }
        end

        def routes
          @routes
        end
      end
    end

    initializer "shakha.routes" do |app|
      Shakha::EngineRouter.draw do
        get "/auth/shakha", to: "auth#new", as: :new_auth
        get "/auth/shakha/authorize", to: "auth#authorize", as: :authorize
        get "/auth/shakha/callback", to: "auth#callback", as: :callback
        post "/auth/shakha/token", to: "auth#token", as: :token
        get "/auth/shakha/error", to: "auth#error", as: :error

        get "/auth/shakha/session", to: "session#show", as: :session
        post "/auth/shakha/session/check", to: "session#check", as: :check_session
        delete "/auth/shakha/session", to: "session#destroy", as: :destroy_session

        get "/.well-known/jwks.json", to: "jwks#show"
        get "/.well-known/openid-configuration", to: "openid#configuration"
      end

      Shakha::EngineRouter.routes.each do |route|
        case route[:type]
        when :get
          app.routes.append do
            get route[:path], to: route[:to], as: route[:as]
          end
        when :post
          app.routes.append do
            post route[:path], to: route[:to], as: route[:as]
          end
        when :match
          app.routes.append do
            match route[:path], to: route[:to], as: route[:as], via: route[:via]
          end
        end
      end
    end
  end
end