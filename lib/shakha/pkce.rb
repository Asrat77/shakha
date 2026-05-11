# frozen_string_literal: true

require "json"
require "active_support/concern"

module Shakha
  module PKCEMixin
    extend ActiveSupport::Concern

    CODE_VERIFIER_LENGTH = 64
    CODE_CHALLENGE_METHOD = "S256"
    PKCE_COOKIE_NAME = "shakha_pkce"
    PKCE_COOKIE_EXPIRY_SECONDS = 600

    class << self
      def generate_code_verifier
        SecureRandom.urlsafe_base64(CODE_VERIFIER_LENGTH)
          .tr("-_", "+/")
          .slice(0, CODE_VERIFIER_LENGTH)
      end

      def generate_code_challenge(verifier)
        Base64.urlsafe_encode64(
          OpenSSL::Digest::SHA256.digest(verifier),
          padding: false
        )
      end
    end

    private

    def create_pkce_bundle
      verifier = PKCEMixin.generate_code_verifier
      challenge = PKCEMixin.generate_code_challenge(verifier)
      state = SecureRandom.urlsafe_base64(32)
      return_to = params[:return_to] || "/"

      pkce_record = {
        verifier: verifier,
        return_to: return_to
      }

      cookies[PKCE_COOKIE_NAME] = {
        value: pkce_record.merge(state: state).to_json,
        httponly: true,
        secure: Rails.env.production?,
        same_site: :lax,
        expires: Time.now.utc + PKCE_COOKIE_EXPIRY_SECONDS
      }

      { challenge: challenge, state: state }
    end

    def verify_pkce!(code_verifier, state_param)
      pkce_json = cookies[PKCE_COOKIE_NAME]

      raise PKCEError, "No PKCE session found" unless pkce_json

      pkce_data = JSON.parse(pkce_json).with_indifferent_access

      raise PKCEError, "No PKCE session found" unless pkce_data

      stored_state = pkce_data[:state]
      stored_verifier = pkce_data[:verifier]
      stored_return_to = pkce_data[:return_to]

      cookies.delete(PKCE_COOKIE_NAME)

      raise PKCEError, "State mismatch" unless stored_state == state_param

      computed = PKCEMixin.generate_code_challenge(code_verifier)
      code_challenge = params[:code_challenge]

      if code_challenge.present?
        raise PKCEError, "Invalid code verifier" unless computed == code_challenge
      end

      { verifier: stored_verifier, return_to: stored_return_to }
    end

    def pkce_state
      pkce_json = cookies[PKCE_COOKIE_NAME]
      return nil unless pkce_json

      JSON.parse(pkce_json).with_indifferent_access
    end
  end

  class PKCEError < StandardError; end
  class GoogleOAuthError < StandardError; end
end