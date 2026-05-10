# frozen_string_literal: true

module Shakha
  class OpenidController < ApplicationController
    def configuration
      render json: {
        issuer: Shakha.config.issuer,
        authorization_endpoint: "#{Shakha.config.service_base_url}/auth/shakha/authorize",
        token_endpoint: "#{Shakha.config.service_base_url}/auth/shakha/token",
        userinfo_endpoint: "#{Shakha.config.service_base_url}/auth/shakha/session",
        jwks_uri: "#{Shakha.config.service_base_url}/.well-known/jwks.json",
        response_types_supported: ["code"],
        grant_types_supported: ["authorization_code"],
        code_challenge_methods_supported: ["S256"],
        subject_types_supported: ["pairwise"],
        id_token_signing_alg_values_supported: ["ES256"],
        scopes_supported: ["openid", "email", "profile"]
      }, content_type: "application/json"
    end
  end
end