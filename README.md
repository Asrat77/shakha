# Shakha

Headless Google OAuth broker for Rails — PKCE, pairwise subjects, zero JavaScript.

Same Google account, different IDs per application. Built DHH-style: database sessions, Turbo native, single "Continue with Google" button.

## Installation

```ruby
gem "shakha"
```

Run the migration:

```bash
bin/rails generate migration CreateShakhaTables
```

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
      t.string :provider, null: false
      t.string :uid, null: false
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

## Configuration

Create `config/initializers/shakha.rb`:

```ruby
Shakha.setup do |config|
  config.app_origin = ENV.fetch("SHAKHA_APP_ORIGIN", "http://localhost:3000")
  config.service_url = ENV["SHAKHA_SERVICE_URL"]        # omit for embedded mode
  config.service_secret = ENV["SHAKHA_SERVICE_SECRET"]
  config.google_client_id = ENV["GOOGLE_CLIENT_ID"]
  config.google_client_secret = ENV["GOOGLE_CLIENT_SECRET"]
  config.session_lifetime = 30.days
end
```

Environment variables:

```bash
export SHAKHA_APP_ORIGIN="https://yourapp.com"
export SHAKHA_SERVICE_SECRET="your-secret-key"
export GOOGLE_CLIENT_ID="your-google-client-id"
export GOOGLE_CLIENT_SECRET="your-google-client-secret"
```

Google Cloud Console redirect URI: `https://yourapp.com/auth/shakha/callback`

## Usage

### Sign In

```erb
<%= link_to "Sign in with Google", shakha.new_auth_path %>
```

### Protect Routes

```ruby
class ApplicationController < ActionController::Base
  include Shakha::ControllerHelpers
  before_action :authenticate!
end
```

### Current User

```ruby
current_user        # Shakha::User or nil
current_session     # Shakha::Session or nil
signed_in?          # boolean
authenticate!       # redirects to login if not signed in
```

### Sign Out

```erb
<%= link_to "Sign out", shakha.session_path, data: { turbo_method: :delete } %>
```

### JWT Verification (API Mode)

```ruby
payload = Shakha.verify_token(id_token)
user_id = payload[:pairwise_sub]
```

## Architecture

- **PKCE** — S256 code challenges on every flow
- **Pairwise subjects** — domain-scoped user identifiers (HMAC-SHA256)
- **ES256 JWTs** — signed with JWKS endpoint at `.well-known/jwks.json`
- **OpenID Connect** — `.well-known/openid-configuration` endpoint
- **Database sessions** — DHH-style, no Redis
- **Turbo native** — zero JavaScript needed
- **Embedded or standalone** — runs as Rails engine or headless service

## Modes

### Embedded (default)

Mount in your Rails app. Routes served at `/auth/shakha`. Uses the app's own `shakha_clients` table with a single client auto-created on first request.

### Service (multi-tenant)

Set `SHAKHA_SERVICE_URL` and register each app's origin in `shakha_clients`. Each app gets different pairwise subjects for the same Google user.

## License

MIT
