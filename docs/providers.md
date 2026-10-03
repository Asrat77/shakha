# Writing your own provider

Shakha ships Google and GitHub. Any other OAuth 2.0 provider is a small Ruby
class that implements the `Shakha::Providers::Base` contract, plus one line to
register it. The controller never special-cases a provider, so a third-party
provider gets the same flow as the built-ins: PKCE, `state`, the one-time
exchange code, the session cookie and Bearer token.

## The contract

Subclass `Shakha::Providers::Base` and implement these five methods. Shakha
creates a new instance per request with `.new` (no arguments).

### `provider_name` → Symbol

The provider's name. It must match the name you register and list in
`config.providers`, and it becomes the URL segment (`/auth/shakha/gitlab`) and
the `provider` column on `Shakha::User`.

### `scopes` → Array of Strings

The OAuth scopes to request. `Base` returns `[]`.

### `authorize_url(state:, code_challenge:, redirect_uri:, nonce: nil)` → String

The full URL to send the browser to. Include `state` and `redirect_uri`
unchanged. If the provider supports PKCE, send `code_challenge` with
`code_challenge_method: "S256"`. If it supports OpenID Connect, send `nonce`
and check it in `identity_from_response`. Providers without PKCE or nonce
support (GitHub, for example) accept the keywords and ignore them.

### `exchange_code(code:, code_verifier:, redirect_uri:)` → Hash

POST to the provider's token endpoint and return the parsed JSON response.
Send `code_verifier` if the provider supports PKCE. Raise `Shakha::OAuthError`
on a non-2xx response or a network failure; Shakha turns that into a clean
error redirect (or a 401 JSON response) and emits `shakha.auth_failure`.

### `identity_from_response(token_response, expected_nonce: nil)` → Hash

Turn the token response into the user's identity. Usually this means calling
the provider's user-info API with the access token. Return exactly this shape:

```ruby
{
  provider: :gitlab,         # same as provider_name
  uid: "12345",              # stable, unique per provider user, as a String
  email: "user@example.com", # may be nil if the provider withholds it
  name: "Ada Lovelace",
  picture: "https://..."     # avatar URL, may be nil
}
```

Shakha finds or creates the `Shakha::User` by `provider` + `uid` and refreshes
`email`, `name` and `picture` on every sign-in. Raise `Shakha::OAuthError` if
the response is unusable (no access token, a nonce mismatch, and so on).

## Credentials

`Shakha::Config` only carries the Google and GitHub keys. A third-party provider
reads its own credentials: accept them as constructor keyword arguments with
`ENV` defaults, as below, so production reads the environment and tests can
pass values directly.

## Worked example: GitLab

GitLab supports PKCE. Its endpoints are `https://gitlab.com/oauth/authorize`
and `https://gitlab.com/oauth/token`, and `GET /api/v4/user` returns the
profile. This exact class is exercised end to end in Shakha's own test suite
(`test/support/gitlab_provider.rb`).

```ruby
# app/lib/gitlab_provider.rb (or lib/, anywhere your app loads code from)
require "net/http"
require "uri"

class GitLabProvider < Shakha::Providers::Base
  AUTHORIZE_URL = "https://gitlab.com/oauth/authorize"
  TOKEN_URL = "https://gitlab.com/oauth/token"
  USER_API_URL = "https://gitlab.com/api/v4/user"

  def initialize(client_id: ENV["GITLAB_CLIENT_ID"], client_secret: ENV["GITLAB_CLIENT_SECRET"])
    super()
    @client_id = client_id
    @client_secret = client_secret
  end

  def provider_name
    :gitlab
  end

  def scopes
    %w[read_user]
  end

  def authorize_url(state:, code_challenge:, redirect_uri:, nonce: nil)
    params = {
      client_id: @client_id,
      redirect_uri: redirect_uri,
      response_type: "code",
      scope: scopes.join(" "),
      state: state,
      code_challenge: code_challenge,
      code_challenge_method: "S256"
    }

    "#{AUTHORIZE_URL}?#{URI.encode_www_form(params)}"
  end

  def exchange_code(code:, code_verifier:, redirect_uri:)
    response = request(Net::HTTP::Post.new(URI(TOKEN_URL)), form: {
      grant_type: "authorization_code",
      code: code,
      code_verifier: code_verifier,
      redirect_uri: redirect_uri,
      client_id: @client_id,
      client_secret: @client_secret
    })

    JSON.parse(response.body)
  end

  def identity_from_response(token_response, expected_nonce: nil)
    access_token = token_response["access_token"]
    raise Shakha::OAuthError, "No access_token received" unless access_token

    get = Net::HTTP::Get.new(URI(USER_API_URL))
    get["Authorization"] = "Bearer #{access_token}"
    user = JSON.parse(request(get).body)

    {
      provider: :gitlab,
      uid: user["id"].to_s,
      email: user["email"],
      name: user["name"] || user["username"],
      picture: user["avatar_url"]
    }
  end

  private

  def request(req, form: nil)
    req["Accept"] = "application/json"
    req.set_form_data(form) if form

    response = Net::HTTP.start(req.uri.host, req.uri.port, use_ssl: true,
                               open_timeout: 5, read_timeout: 10) { |http| http.request(req) }
    raise Shakha::OAuthError, "GitLab returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    response
  rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError => e
    raise Shakha::OAuthError, "Unable to reach GitLab: #{e.message}"
  end
end
```

## Registering it

```ruby
# config/initializers/shakha.rb
Shakha.setup do |config|
  # ...
  config.providers = [ :google, :gitlab ]
end

Rails.application.config.to_prepare do
  Shakha::Providers.register(:gitlab, "GitLabProvider")
end
```

`register(name, klass)` takes the provider class or its name as a String. Pass
a String when the class lives in an autoloaded directory, so code reloading in
development picks up your changes. Registering inside `to_prepare` also keeps
the registration in place across reloads.

Registering a name that already exists replaces it, including the built-ins:
`Shakha::Providers.register(:github, "MyGitHubEnterpriseProvider")` swaps out
the GitHub provider. `Shakha::Providers.registered` lists every registered name.

A registered provider still has to be listed in `config.providers` to be
reachable; unlisted providers return 404.

Then add the callback URL to the provider's OAuth application settings:
`https://api.example.com/auth/shakha/gitlab/callback`, derived from
`APP_ORIGIN` and the mount point. Send users to `/auth/shakha/gitlab` to sign in.
The built-in sign-in page shows a "Continue with Gitlab" button automatically.

## Testing it

Stub the provider's HTTP endpoints with [WebMock](https://github.com/bblimke/webmock),
the same way Shakha tests its built-ins:

```ruby
require "test_helper"
require "webmock/minitest"

class GitLabProviderTest < ActiveSupport::TestCase
  setup { @provider = GitLabProvider.new(client_id: "gl_id", client_secret: "gl_secret") }

  test "provider_name" do
    assert_equal :gitlab, @provider.provider_name
  end

  test "builds an authorize URL with PKCE" do
    url = @provider.authorize_url(
      state: "st", code_challenge: "ch",
      redirect_uri: "http://localhost:3000/auth/shakha/gitlab/callback"
    )
    params = URI.decode_www_form(URI.parse(url).query).to_h

    assert_equal "gl_id", params["client_id"]
    assert_equal "st", params["state"]
    assert_equal "ch", params["code_challenge"]
    assert_equal "S256", params["code_challenge_method"]
  end

  test "exchanges a code for an access token" do
    stub_request(:post, "https://gitlab.com/oauth/token")
      .to_return(status: 200, body: { access_token: "glpat" }.to_json,
                 headers: { "Content-Type" => "application/json" })

    response = @provider.exchange_code(code: "c", code_verifier: "v",
                                       redirect_uri: "http://localhost:3000/cb")
    assert_equal "glpat", response["access_token"]
  end

  test "fetches user identity from the GitLab API" do
    stub_request(:get, "https://gitlab.com/api/v4/user")
      .with(headers: { "Authorization" => "Bearer glpat" })
      .to_return(status: 200, body: {
        id: 7, username: "tanuki", name: "Tanuki",
        email: "tanuki@gitlab.com", avatar_url: "https://gitlab.example/7.png"
      }.to_json, headers: { "Content-Type" => "application/json" })

    identity = @provider.identity_from_response({ "access_token" => "glpat" })

    assert_equal :gitlab, identity[:provider]
    assert_equal "7", identity[:uid]
    assert_equal "tanuki@gitlab.com", identity[:email]
  end

  test "raises when no access_token is present" do
    assert_raises(Shakha::OAuthError) { @provider.identity_from_response({}) }
  end
end
```
