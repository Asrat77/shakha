# frozen_string_literal: true

require_relative "../test_helper"

module Shakha
  class PKCETest < ActiveSupport::TestCase
    test "generates RFC 7636 compliant code verifier" do
      verifier = PKCEMixin.generate_code_verifier

      assert verifier.length.between?(43, 128)
      assert_match(/\A[A-Za-z0-9\-._~]+\z/, verifier)
    end

    test "code verifier contains no disallowed characters" do
      100.times do
        verifier = PKCEMixin.generate_code_verifier
        refute_match(/[+\/]/, verifier)
      end
    end

    test "generates consistent code challenge" do
      verifier = PKCEMixin.generate_code_verifier
      challenge = PKCEMixin.generate_code_challenge(verifier)

      recomputed = PKCEMixin.generate_code_challenge(verifier)
      assert_equal challenge, recomputed
    end

    test "challenge is valid base64url without padding" do
      verifier = "a" * 64
      challenge = PKCEMixin.generate_code_challenge(verifier)

      assert_match(/\A[A-Za-z0-9\-_]+\z/, challenge)
      refute challenge.end_with?("=")
    end
  end
end
