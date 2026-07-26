# frozen_string_literal: true

require_relative "../test_helper"

module Shakha
  class SessionTest < ActiveSupport::TestCase
    test "generates a token on create" do
      session = create_session_record
      assert session.token.present?
      assert_operator session.token.length, :>=, 43
    end

    test "does not overwrite an explicit token" do
      session = Shakha::Session.create!(user: create_user, token: "explicit")
      assert_equal "explicit", session.token
    end

    test "active scope excludes expired sessions" do
      fresh = create_session_record
      stale = create_session_record(user: create_user(uid: "other"))
      stale.update_columns(created_at: (Shakha.config.session_lifetime + 1.day).ago)

      assert_includes Shakha::Session.active, fresh
      refute_includes Shakha::Session.active, stale
      assert stale.expired?
      refute fresh.expired?
    end

    test "expires_at is created_at plus lifetime" do
      session = create_session_record
      assert_in_delta (session.created_at + Shakha.config.session_lifetime).to_f,
                      session.expires_at.to_f, 1.0
    end
  end
end
