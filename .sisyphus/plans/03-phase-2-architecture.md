# Phase 2: Architecture — SPA-First OAuth Broker

Strip service infrastructure. Keep the JSON API. Add the SPA token redirect flow.

---

## Modules to DELETE

| File | Reason |
|---|---|
| `lib/shakha/jwt_handler.rb` | ES256/JWKS/OIDC — overkill. Session tokens are random strings. |
| `lib/shakha/pairwise.rb` | Domain-scoped IDs. Clever but nobody asked. |
| `lib/shakha/middleware.rb` | Token verification middleware. Handle in-controller instead. |
| `lib/shakha/auditable.rb` | Broken (`@current_client` never set). Adds nothing. |
| `app/controllers/shakha/openid_controller.rb` | OIDC discovery — service infra |
| `app/controllers/shakha/jwks_controller.rb` | JWKS endpoint — service infra |

## Routes — NEW

```ruby
# lib/shakha/engine.rb
routes do
  root to: "auth#new"

  # OAuth flow — just the provider name, no /authorize suffix
  get  ":provider"          => "auth#authorize"
  get  ":provider/callback" => "auth#callback"

  # Session management (JSON API)
  get  "session"        => "session#show"
  get  "session/check"  => "session#check"

  # Sign out
  delete "sign_out" => "auth#destroy"

  # Error page
  get "error" => "auth#error"
end
```

URLs the frontend dev needs:
```
/auth/shakha/google          — sign in with Google
/auth/shakha/github          — sign in with GitHub
/auth/shakha/session          — get current user (JSON)
/auth/shakha/session/check    — is session valid? (lightweight JSON)
/auth/shakha/sign_out         — sign out (DELETE)
```

---

## AuthController — The Core Flow

```ruby
module Shakha
  class AuthController < ApplicationController
    include PKCEMixin

    skip_before_action :verify_authenticity_token, only: [:callback]

    # GET /auth/shakha — Optional sign-in page (Rails monolith)
    def new
      @client = find_or_create_client
      @return_to = sanitize_return_to(params[:return_to])
      @providers = Shakha.config.providers
    end

    # GET /auth/shakha/:provider/authorize
    def authorize
      provider = resolve_provider
      pkce = create_pkce_bundle

      redirect_uri = "#{Shakha.config.app_origin}/auth/shakha/#{provider.provider_name}/callback"
      auth_url = provider.authorize_url(
        state: pkce[:state],
        code_challenge: pkce[:challenge],
        redirect_uri: redirect_uri
      )

      redirect_to auth_url, allow_other_host: true
    end

    # GET /auth/shakha/:provider/callback
    def callback
      provider = resolve_provider
      pkce_result = verify_pkce!(params[:state])

      # Exchange code for tokens (via provider)
      token_response = provider.exchange_code(
        code: params[:code],
        code_verifier: pkce_result[:verifier],
        redirect_uri: "#{Shakha.config.app_origin}/auth/shakha/#{provider.provider_name}/callback"
      )

      identity = provider.identity_from_response(token_response)
      user = find_or_create_user(provider.provider_name, identity)
      session_record = create_session(user)

      # Set cookie (for Rails monolith flow)
      set_session_cookie(session_record)

      # Redirect with token (for SPA flow)
      redirect_to build_return_url(pkce_result[:return_to], session_record)

    rescue PKCEError, GoogleOAuthError, OAuthError => e
      handle_auth_failure(e, pkce_result)
    end

    # DELETE /auth/shakha/session
    def destroy
      current_session&.destroy
      cookies.delete(:shakha_session_token)

      respond_to do |format|
        format.html { redirect_to params[:return_to].presence || "/" }
        format.json { render json: { status: "signed_out" } }
      end
    end

    # GET /auth/shakha/error
    def error
      @message = params[:message] || "Authentication failed"
    end

    private

    def resolve_provider
      provider_name = (params[:provider] || :google).to_sym
      Shakha::Providers.resolve(provider_name)
    end

    def find_or_create_user(provider_name, identity)
      Shakha::User.find_or_create_by!(
        provider: provider_name.to_s,
        uid: identity[:uid]
      ) do |user|
        user.client = find_or_create_client
        user.email = identity[:email]
        user.name = identity[:name]
        user.picture = identity[:picture]
      end
    end

    def create_session(user)
      Shakha::Session.create!(
        user: user,
        client: find_or_create_client,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
    end

    def set_session_cookie(session_record)
      cookies.encrypted[:shakha_session_token] = {
        value: session_record.token,
        httponly: true,
        secure: Rails.env.production?,
        same_site: :lax,
        expires: Shakha.config.session_lifetime.from_now
      }
    end

    def build_return_url(return_to, session_record)
      uri = URI.parse(return_to || "/")
      params = URI.decode_www_form(uri.query || "").to_h
      params["token"] = session_record.token
      params["expires_at"] = session_record.expires_at.iso8601
      uri.query = URI.encode_www_form(params)
      uri.to_s
    end

    def handle_auth_failure(exception, pkce_result)
      return_to = pkce_result&.dig(:return_to) || "/"

      if request.format.json? || api_request?
        render json: { error: user_facing_error(exception) }, status: :unauthorized
      else
        redirect_to "#{return_to}?error=#{URI.encode_www_form_component(user_facing_error(exception))}"
      end
    end

    def api_request?
      request.headers["Accept"]&.include?("application/json")
    end

    def sanitize_return_to(raw)
      return "/" if raw.blank?
      uri = URI.parse(raw)
      return "/" unless uri.path.present? && uri.path.start_with?("/")
      return "/" if uri.host.present? && uri.host != URI.parse(Shakha.config.app_origin).host
      raw
    rescue URI::InvalidURIError
      "/"
    end

    def find_or_create_client
      origin = request.origin || Shakha.config.app_origin
      origin_uri = URI.parse(origin).origin
      Shakha::Client.find_or_create_by!(origin: origin_uri) do |client|
        client.name = URI.parse(origin).host
      end
    end

    def user_facing_error(exception)
      case exception
      when PKCEError then "Authentication failed. Please try again."
      when OAuthError then "Unable to sign in. Please try again later."
      else "An unexpected error occurred. Please try again."
      end
    end
  end
end
```

---

## SessionController — JSON API for SPAs

```ruby
module Shakha
  class SessionController < ApplicationController
    # GET /auth/shakha/session — Current user info (SPA hydrates user from this)
    def show
      unless signed_in?
        return render json: { error: "Authentication required" }, status: :unauthorized
      end

      render json: {
        user: {
          id: current_user.id,
          email: current_user.email,
          name: current_user.name,
          picture: current_user.picture,
          provider: current_user.provider
        },
        session: {
          expires_at: current_session.expires_at.iso8601
        }
      }
    end

    # GET /auth/shakha/session/check — Lightweight: is the token still valid?
    def check
      if signed_in?
        render json: { status: "active" }
      else
        render json: { status: "expired" }, status: :unauthorized
      end
    end
  end
end
```

---

## ControllerHelpers — Cookie + Bearer Auth

```ruby
module Shakha
  module ControllerHelpers
    extend ActiveSupport::Concern

    included do
      helper_method :current_user, :current_session, :signed_in?
    end

    private

    def current_session
      return @current_session if defined?(@current_session)
      @current_session = find_session_from_cookie || find_session_from_bearer
    end

    def current_user
      current_session&.user
    end

    def signed_in?
      current_session.present?
    end

    def authenticate!
      return if signed_in?

      respond_to do |format|
        format.html { redirect_to shakha.new_auth_path(return_to: request.fullpath) }
        format.json { render json: { error: "Authentication required" }, status: :unauthorized }
      end
    end

    def find_session_from_cookie
      token = cookies.encrypted[:shakha_session_token]
      return unless token
      Shakha::Session.active.find_by(token: token)
    end

    def find_session_from_bearer
      header = request.headers["Authorization"]
      return unless header&.start_with?("Bearer ")

      token = header.delete_prefix("Bearer ")
      Shakha::Session.active.find_by(token: token)
    end
  end
end
```

---

## Models — Simplified

### Shakha::User
```ruby
module Shakha
  class User < ::ApplicationRecord
    self.table_name = "shakha_users"

    belongs_to :client, class_name: "Shakha::Client"
    has_many :sessions, class_name: "Shakha::Session", dependent: :destroy

    validates :provider, presence: true
    validates :uid, presence: true
    validates :uid, uniqueness: { scope: :provider }

    def self.find_by_identity(provider:, uid:)
      find_by(provider: provider.to_s, uid: uid)
    end
  end
end
```

### Shakha::Session
```ruby
module Shakha
  class Session < ::ApplicationRecord
    self.table_name = "shakha_sessions"

    belongs_to :user, class_name: "Shakha::User", optional: true
    belongs_to :client, class_name: "Shakha::Client"

    before_create :generate_token

    scope :active, -> { where("created_at > ?", Shakha.config.session_lifetime.ago) }

    def expired?
      created_at < Shakha.config.session_lifetime.ago
    end

    def expires_at
      created_at + Shakha.config.session_lifetime
    end

    private

    def generate_token
      self.token ||= SecureRandom.urlsafe_base64(32)
    end
  end
end
```

---

## Config — Minimal

```ruby
module Shakha
  class Config
    attr_accessor :app_origin
    attr_accessor :google_client_id, :google_client_secret
    attr_accessor :github_client_id, :github_client_secret
    attr_accessor :providers
    attr_accessor :session_lifetime
    attr_accessor :rate_limiting_enabled

    def initialize
      @session_lifetime = 30.days
      @rate_limiting_enabled = false
      @providers = [:google]
    end
  end
end
```

Removed: `service_url`, `service_secret`, `issuer`, `signing_key`, `verification_key`, `key_id`, `service_base_url`, `client_id`, `audience` — all service infrastructure.

---

## Migration — New Schema

```ruby
class CreateShakhaTables < ActiveRecord::Migration[7.1]
  def change
    create_table :shakha_clients do |t|
      t.string :name, null: false
      t.string :origin, null: false
      t.timestamps
      t.index :origin, unique: true
    end

    create_table :shakha_users do |t|
      t.references :client, null: false, foreign_key: { to_table: :shakha_clients }
      t.string :provider, null: false                    # "google", "github"
      t.string :uid, null: false                         # Provider's user ID
      t.string :email
      t.string :name
      t.string :picture
      t.timestamps
      t.index [:provider, :uid], unique: true
      t.index :email
    end

    create_table :shakha_sessions do |t|
      t.references :user, foreign_key: { to_table: :shakha_users }
      t.references :client, null: false, foreign_key: { to_table: :shakha_clients }
      t.string :token, null: false
      t.string :ip_address
      t.string :user_agent
      t.timestamps
      t.index :token, unique: true
      t.index :created_at
    end
  end
end
```

Key changes from original:
- `provider` + `uid` instead of `pairwise_sub`
- Sessions have `ip_address`, `user_agent` (fixes Bug #3)
- No `jti` column (no JWTs)
- No `pairwise_sub` unique index
