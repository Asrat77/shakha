# frozen_string_literal: true

require_relative "../test_helper"

module Shakha
  class PKCETest < ActiveSupport::TestCase
    test "generates valid code verifier" do
      verifier = PKCEMixin.generate_code_verifier

      assert_equal 64, verifier.length
      assert verifier.match?(/^[A-Za-z0-9_-]+$/)
    end

    test "generates consistent code challenge" do
      verifier = PKCEMixin.generate_code_verifier
      challenge = PKCEMixin.generate_code_challenge(verifier)

      recomputed = PKCEMixin.generate_code_challenge(verifier)
      assert_equal challenge, recomputed
    end

    test "challenge is base64url encoded" do
      verifier = "a" * 64
      challenge = PKCEMixin.generate_code_challenge(verifier)

      decoded = Base64.urlsafe_decode64(challenge)
      assert_equal 32, decoded.length
    end
  end
end