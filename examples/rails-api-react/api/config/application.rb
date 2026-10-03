require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

module Api
  class Application < Rails::Application
    config.middleware.use ActionDispatch::Cookies
    config.load_defaults 8.1
    config.api_only = true
  end
end
