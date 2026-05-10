# frozen_string_literal: true

require "jwt"

module Shakha
  class ConfigurationError < StandardError; end
  class JWTError < StandardError; end

  class JwtHandler
    ALGORITHM = "ES256"

    class << self
      def encode(payload, exp: 24.hours.from_now)
        secret = signing_key || raise(ConfigurationError, "RSA/EC private key required for signing")

        header = {
          alg: ALGORITHM,
          typ: "JWT",
          kid: key_id
        }

        payload = payload.with_indifferent_access.merge(
          iss: Shakha.config.issuer,
          aud: Shakha.config.audience,
          iat: Time.current.to_i,
          exp: exp.to_i,
          jti: SecureRandom.uuid
        )

        JWT.encode(payload, secret, ALGORITHM, header)
      end

      def verify(token, audience: nil)
        public_key = verification_key || raise(ConfigurationError, "RSA/EC public key required for verification")

        decoded = JWT.decode(
          token,
          public_key,
          true,
          {
            algorithm: ALGORITHM,
            iss: Shakha.config.issuer,
            aud: audience || Shakha.config.audience,
            verify_iss: true,
            verify_aud: true,
            verify_expiration: true
          }
        )

        decoded[0].with_indifferent_access
      rescue JWT::DecodeError => e
        raise JWTError, e.message
      end

      def jwks
        {
          keys: [
            {
              kty: "EC",
              crv: "P-256",
              x: Base64.urlsafe_encode64(public_key_point&.x || public_key_raw_point[0..31], padding: false),
              y: Base64.urlsafe_encode64(public_key_point&.y || public_key_raw_point[32..63], padding: false),
              use: "sig",
              alg: ALGORITHM,
              kid: key_id
            }
          ]
        }.to_json
      end

      private

      def signing_key
        return @signing_key if defined?(@signing_key)

        key_material = Shakha.config.signing_key
        return @signing_key = nil unless key_material

        if key_material.is_a?(OpenSSL::PKey::EC)
          @signing_key = key_material
        elsif key_material.start_with?("-----BEGIN")
          @signing_key = OpenSSL::PKey::EC.new(key_material)
        else
          @signing_key = OpenSSL::PKey::EC.new(Base64.decode64(key_material))
        end
      end

      def verification_key
        return signing_key&.public_key if signing_key

        public_material = Shakha.config.verification_key
        return nil unless public_material

        if public_material.start_with?("-----BEGIN")
          OpenSSL::PKey::EC.new(public_material)
        else
          OpenSSL::PKey::EC.new(Base64.decode64(public_material))
        end
      end

      def public_key_point
        @public_key_point ||= begin
          key = verification_key || signing_key&.public_key
          return nil unless key

          group = key.group
          point = key.public_key
          { x: point.x, y: point.y }
        end
      end

      def public_key_raw_point
        @public_key_raw_point ||= begin
          key = verification_key || signing_key&.public_key
          return nil unless key

          point = key.public_key
          [point.x, point.y].map { |n| n.to_s(16).rjust(64, "0") }.join.scan(/../).map { |b| b.to_i(16).chr }.join
        end
      end

      def key_id
        Shakha.config.key_id || "default"
      end
    end
  end
end