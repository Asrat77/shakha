# frozen_string_literal: true

require "active_support/concern"

module Shakha
  module PKCEMixin
    extend ActiveSupport::Concern

    CODE_VERIFIER_LENGTH = 64
    CODE_CHALLENGE_METHOD = "S256"

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

      session[:shakha_pkce] = {
        verifier: verifier,
        state: state,
        return_to: params[:return_to] || request.referer || "/"
      }

      { challenge: challenge, state: state }
    end

    def verify_pkce!(code_verifier)
      stored = session[:shakha_pkce]

      raise PKCEError, "No PKCE session found" unless stored
      raise PKCEError, "State mismatch" unless stored[:state] == params[:state]

      computed = PKCEMixin.generate_code_challenge(code_verifier)
      raise PKCEError, "Invalid code verifier" unless computed == params[:code_challenge]

      session.delete(:shakha_pkce)
      stored[:verifier]
    end

    def pkce_state
      session[:shakha_pkce]
    end
  end

  class PKCEError < StandardError; end
  class GoogleOAuthError < StandardError; end
end