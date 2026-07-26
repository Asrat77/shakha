# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
ENV["DATABASE_URL"] = "sqlite3::memory:"

require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"

require_relative "../lib/shakha"

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

class DummyApp < Rails::Application
  config.load_defaults Rails::VERSION::STRING.to_f
  config.eager_load = false
  config.secret_key_base = "shakha-test-secret-key-base-not-for-production"
  config.hosts.clear
  config.logger = ActiveSupport::Logger.new(File::NULL)
  config.action_dispatch.show_exceptions = :none
  config.cache_store = :memory_store
end

Shakha.setup do |config|
  config.app_origin = "http://localhost:3000"
  config.google_client_id = "test_client_id"
  config.google_client_secret = "test_client_secret"
  config.github_client_id = "gh_test_id"
  config.github_client_secret = "gh_test_secret"
  config.providers = [ :google, :github ]
end

Rails.application.initialize!

ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :shakha_users do |t|
    t.string :provider, null: false
    t.string :uid, null: false
    t.string :email
    t.string :name
    t.string :picture
    t.timestamps
    t.index %i[provider uid], unique: true
    t.index :email
  end

  create_table :shakha_sessions do |t|
    t.references :user
    t.string :token, null: false
    t.string :ip_address
    t.string :user_agent
    t.timestamps
    t.index :token, unique: true
    t.index :created_at
  end
end

class ProtectedController < ActionController::Base
  include Shakha::ControllerHelpers

  before_action :authenticate!

  def show
    render json: { id: current_user.id, email: current_user.email }
  end
end

Rails.application.routes.draw do
  mount Shakha::Engine => "/auth/shakha"
  get "/protected", to: "protected#show"
end

require "minitest/autorun"
require "webmock/minitest"

module ShakhaTestHelpers
  def create_user(provider: "google", uid: "uid_123", email: nil)
    Shakha::User.create!(
      provider: provider, uid: uid,
      email: email || "#{uid}@example.com", name: "Test User",
      picture: "https://example.com/p.jpg"
    )
  end

  def create_session_record(user: nil)
    user ||= create_user
    Shakha::Session.create!(user: user)
  end
end

class ActiveSupport::TestCase
  include ShakhaTestHelpers

  setup do
    Shakha::Session.delete_all
    Shakha::User.delete_all
    Shakha.config.allowed_redirect_origins = nil
    Shakha.config.rate_limiting_enabled = false
  end
end
