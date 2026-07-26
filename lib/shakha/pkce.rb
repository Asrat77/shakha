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
        SecureRandom.urlsafe_base64(CODE_VERIFIER_LENGTH, false)
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
      nonce = SecureRandom.urlsafe_base64(32)
      # sanitize_return_to is provided by the including controller (AuthController);
      # validating here means the stored return_to is always safe to redirect to.
      return_to = sanitize_return_to(params[:return_to])

      pkce_record = {
        verifier: verifier,
        return_to: return_to,
        nonce: nonce
      }

      cookies.encrypted[PKCE_COOKIE_NAME] = {
        value: pkce_record.merge(state: state).to_json,
        httponly: true,
        secure: Rails.env.production?,
        same_site: :lax,
        expires: Time.now.utc + PKCE_COOKIE_EXPIRY_SECONDS
      }

      { challenge: challenge, state: state, nonce: nonce }
    end

    def verify_pkce!(state_param)
      pkce_json = cookies.encrypted[PKCE_COOKIE_NAME]

      raise PKCEError, "No PKCE session found" unless pkce_json

      pkce_data = JSON.parse(pkce_json).with_indifferent_access

      raise PKCEError, "No PKCE session found" unless pkce_data

      stored_state = pkce_data[:state]
      stored_verifier = pkce_data[:verifier]
      stored_return_to = pkce_data[:return_to]
      stored_nonce = pkce_data[:nonce]

      cookies.delete(PKCE_COOKIE_NAME)

      raise PKCEError, "State mismatch" unless ActiveSupport::SecurityUtils.secure_compare(stored_state.to_s, state_param.to_s)

      { verifier: stored_verifier, return_to: stored_return_to, nonce: stored_nonce }
    end

    def pkce_state
      pkce_json = cookies.encrypted[PKCE_COOKIE_NAME]
      return nil unless pkce_json

      JSON.parse(pkce_json).with_indifferent_access
    end
  end

  class PKCEError < StandardError; end
end
