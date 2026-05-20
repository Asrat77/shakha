# Phase 3: Multi-Provider — Google + GitHub from Day One

## Provider System

### Base class
**File**: `lib/shakha/providers/base.rb`

```ruby
module Shakha
  module Providers
    class Base
      def authorize_url(state:, code_challenge:, redirect_uri:)
        raise NotImplementedError
      end

      def exchange_code(code:, code_verifier:, redirect_uri:)
        raise NotImplementedError
      end

      def identity_from_response(token_response)
        raise NotImplementedError
      end

      def provider_name
        raise NotImplementedError
      end

      def scopes
        []
      end

      def extra_authorize_params
        {}
      end
    end
  end
end
```

### Provider Registry
**File**: `lib/shakha/providers.rb`

```ruby
module Shakha
  module Providers
    PROVIDER_MAP = {
      google: "Shakha::Providers::Google",
      github: "Shakha::Providers::GitHub"
    }.freeze

    def self.resolve(name)
      class_name = PROVIDER_MAP[name.to_sym] || raise("Unknown provider: #{name}")
      class_name.constantize.new
    end
  end
end
```

---

### Google Provider
**File**: `lib/shakha/providers/google.rb`

```ruby
module Shakha
  module Providers
    class Google < Base
      AUTHORIZE_URL = "https://accounts.google.com/o/oauth2/v2/auth"
      TOKEN_URL = "https://oauth2.googleapis.com/token"

      def provider_name
        :google
      end

      def authorize_url(state:, code_challenge:, redirect_uri:)
        params = {
          client_id: Shakha.config.google_client_id,
          redirect_uri: redirect_uri,
          response_type: "code",
          scope: scopes.join(" "),
          code_challenge: code_challenge,
          code_challenge_method: "S256",
          state: state,
          access_type: "offline",
          prompt: "consent",
          nonce: SecureRandom.urlsafe_base64(32)
        }

        "#{AUTHORIZE_URL}?#{URI.encode_www_form(params)}"
      end

      def exchange_code(code:, code_verifier:, redirect_uri:)
        response = http_post(TOKEN_URL, {
          code: code,
          client_id: Shakha.config.google_client_id,
          client_secret: Shakha.config.google_client_secret,
          redirect_uri: redirect_uri,
          grant_type: "authorization_code",
          code_verifier: code_verifier
        })

        JSON.parse(response.body)
      end

      def identity_from_response(token_response)
        id_token = token_response["id_token"]
        raise OAuthError, "No id_token received" unless id_token

        payload = JWT.decode(id_token, nil, false)[0]

        {
          provider: :google,
          uid: payload["sub"],
          email: payload["email"],
          name: payload["name"],
          picture: payload["picture"]
        }
      end

      def scopes
        %w[openid email profile]
      end

      private

      def http_post(url, body)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 5
        http.read_timeout = 10

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "application/x-www-form-urlencoded"
        request.body = URI.encode_www_form(body)

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise OAuthError, "#{provider_name} returned #{response.code}: #{response.body.truncate(200)}"
        end

        response
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError => e
        raise OAuthError, "Unable to reach #{provider_name}: #{e.message}"
      end
    end
  end
end
```

---

### GitHub Provider
**File**: `lib/shakha/providers/github.rb`

```ruby
module Shakha
  module Providers
    class GitHub < Base
      AUTHORIZE_URL = "https://github.com/login/oauth/authorize"
      TOKEN_URL = "https://github.com/login/oauth/access_token"
      USER_API_URL = "https://api.github.com/user"

      def provider_name
        :github
      end

      def authorize_url(state:, code_challenge:, redirect_uri:)
        params = {
          client_id: Shakha.config.github_client_id,
          redirect_uri: redirect_uri,
          scope: scopes.join(" "),
          state: state
        }

        "#{AUTHORIZE_URL}?#{URI.encode_www_form(params)}"
      end

      def exchange_code(code:, code_verifier:, redirect_uri:)
        response = http_post(TOKEN_URL, {
          code: code,
          client_id: Shakha.config.github_client_id,
          client_secret: Shakha.config.github_client_secret,
          redirect_uri: redirect_uri
        }, accept: :json)

        JSON.parse(response.body)
      end

      def identity_from_response(token_response)
        access_token = token_response["access_token"]
        raise OAuthError, "No access_token received" unless access_token

        user_data = fetch_user(access_token)

        {
          provider: :github,
          uid: user_data["id"].to_s,
          email: user_data["email"],
          name: user_data["name"] || user_data["login"],
          picture: user_data["avatar_url"]
        }
      end

      def scopes
        %w[user:email]
      end

      private

      def fetch_user(access_token)
        uri = URI.parse(USER_API_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 5
        http.read_timeout = 10

        request = Net::HTTP::Get.new(uri.request_uri)
        request["Authorization"] = "Bearer #{access_token}"
        request["Accept"] = "application/json"

        response = http.request(request)
        JSON.parse(response.body)
      end

      def http_post(url, body, accept: :json)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 5
        http.read_timeout = 10

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Accept"] = "application/json" if accept == :json
        request["Content-Type"] = "application/x-www-form-urlencoded"
        request.body = URI.encode_www_form(body)

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise OAuthError, "GitHub returned #{response.code}: #{response.body.truncate(200)}"
        end

        response
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError => e
        raise OAuthError, "Unable to reach GitHub: #{e.message}"
      end
    end
  end
end
```

---

## Config Extension

```ruby
# config/initializers/shakha.rb
Shakha.setup do |config|
  config.app_origin = ENV.fetch("APP_ORIGIN", "http://localhost:3000")

  # Google
  config.google_client_id = ENV["GOOGLE_CLIENT_ID"]
  config.google_client_secret = ENV["GOOGLE_CLIENT_SECRET"]

  # GitHub
  config.github_client_id = ENV["GITHUB_CLIENT_ID"]
  config.github_client_secret = ENV["GITHUB_CLIENT_SECRET"]

  # Enable both
  config.providers = [:google, :github]
end
```

---

## Error Classes

```ruby
# lib/shakha.rb
module Shakha
  class ConfigurationError < StandardError; end
  class PKCEError < StandardError; end
  class OAuthError < StandardError; end
end
```

The old `GoogleOAuthError` and `JWTError` are replaced by the generic `OAuthError`.

---

## Files Added in Phase 3

```
lib/shakha/
├── providers.rb              # Registry
├── providers/
│   ├── base.rb               # Abstract base
│   ├── google.rb             # Google implementation
│   └── github.rb             # GitHub implementation
```

## Files Updated in Phase 3

- `lib/shakha.rb` — require providers, update error classes
- `app/controllers/shakha/auth_controller.rb` — use `resolve_provider`
- `app/views/shakha/auth/new.html.erb` — loop over `@providers`
