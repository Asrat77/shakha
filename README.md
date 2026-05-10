# Shakha

Minimal auth broker for Google OAuth with PKCE and pairwise subjects.

## Installation

Add to your Gemfile:

```ruby
gem "shakha"
```

Run the installer:

```bash
rails generate shakha:install
```

Set environment variables:

```bash
export SHAKHA_APP_ORIGIN="https://yourapp.com"
export SHAKHA_SERVICE_SECRET="your-secret-key"
export GOOGLE_CLIENT_ID="your-google-client-id"
export GOOGLE_CLIENT_SECRET="your-google-client-secret"
```

## Configuration

See `config/initializers/shakha.rb` for all options.

## Usage

### Sign In

Redirect users to sign in:

```erb
<%= link_to "Sign in with Google", shakha.new_auth_path %>
```

### Current User

In controllers:

```ruby
class ApplicationController < ActionController::Base
  include Shakha::ControllerHelpers
end
```

```ruby
current_user        # Shakha::User or nil
current_session    # Shakha::Session or nil
signed_in?         # boolean
authenticate!      # redirect to login if not signed in
```

### Protect Routes

```ruby
class PostsController < ApplicationController
  before_action :authenticate!
end
```

### JWT Verification (API Mode)

```ruby
payload = Shakha.verify_token(id_token)
user_id = payload[:sub]
```

## Architecture

- **PKCE** — S256 code challenges on every flow
- **Pairwise subjects** — domain-scoped user identifiers
- **ES256 JWTs** — signed with JWKS endpoint
- **Database sessions** — DHH-style, no Redis
- **Turbo native** — zero JS needed

## License

MIT