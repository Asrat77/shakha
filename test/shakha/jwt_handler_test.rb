# frozen_string_literal: true

require_relative "../test_helper"

module Shakha
  class JwtHandlerTest < ActiveSupport::TestCase
    setup do
      @key = OpenSSL::PKey::EC.generate_key("prime256v1")
      Shakha.config.signing_key = @key.to_pem
      Shakha.config.verification_key = @key.to_pem
      Shakha.config.issuer = "https://test.shakha.dev"
      Shakha.config.audience = "origin:https://myapp.com"
    end

    test "encodes and decodes payload" do
      payload = { sub: "ps_test123", email: "test@example.com" }

      token = JwtHandler.encode(payload)
      decoded = JwtHandler.verify(token)

      assert_equal "ps_test123", decoded[:sub]
      assert_equal "test@example.com", decoded[:email]
      assert_equal "https://test.shakha.dev", decoded[:iss]
      assert_equal "origin:https://myapp.com", decoded[:aud]
    end

    test "includes standard claims" do
      token = JwtHandler.encode({ sub: "test" })
      decoded = JwtHandler.verify(token)

      assert decoded[:iat]
      assert decoded[:exp]
      assert decoded[:jti]
      assert decoded[:iss]
      assert decoded[:aud]
    end

    test "raises on expired token" do
      token = JwtHandler.encode({ sub: "test" }, exp: 1.second.ago)

      assert_raises(JWTError) do
        JwtHandler.verify(token)
      end
    end

    test "raises on wrong audience" do
      token = JwtHandler.encode({ sub: "test" })

      assert_raises(JWTError) do
        JwtHandler.verify(token, audience: "origin:https://other.com")
      end
    end

    test "raises on wrong issuer" do
      original = Shakha.config.issuer
      Shakha.config.issuer = "https://other.issuer"

      token = JwtHandler.encode({ sub: "test" })

      Shakha.config.issuer = original

      assert_raises(JWTError) do
        JwtHandler.verify(token)
      end
    end

    test "generates valid JWKS" do
      jwks = JSON.parse(JwtHandler.jwks)

      assert jwks["keys"]
      assert_equal 1, jwks["keys"].size

      key = jwks["keys"].first
      assert_equal "EC", key["kty"]
      assert_equal "P-256", key["crv"]
      assert_equal "sig", key["use"]
      assert_equal "ES256", key["alg"]
    end
  end
end