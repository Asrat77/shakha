# frozen_string_literal: true

require "base64"
require "openssl"
require "jwt"

module Shakha
  module Pairwise
    HMAC_DIGEST = OpenSSL::Digest::SHA256.new

    class << self
      def derive(google_sub, client_id)
        secret = secret_key
        input = "#{google_sub}:#{client_id}"
        digest = OpenSSL::HMAC.hexdigest(HMAC_DIGEST, secret, input)
        "ps_#{digest}"
      end

      private

      def secret_key
        Shakha.config.service_secret || raise(Shakha::ConfigurationError, "SHAKHA_SECRET not set")
      end
    end
  end
end