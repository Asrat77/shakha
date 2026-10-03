# frozen_string_literal: true

require "net/http"
require "uri"

# The worked example from docs/providers.md, kept here so the guide stays
# honest: test/shakha/custom_provider_test.rb runs it through the full flow.
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
