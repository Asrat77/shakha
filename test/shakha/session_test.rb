# frozen_string_literal: true

require_relative "../test_helper"

module Shakha
  class SessionTest < ActiveSupport::TestCase
    setup do
      @client = Shakha::Client.create!(origin: "https://test.com", name: "Test")
      @user = Shakha::User.create!(provider: "google", uid: "123", client: @client)
    end

    test "generates token on create" do
      session = Shakha::Session.create!(user: @user, client: @client)

      assert session.token.present?
      assert_equal 43, session.token.length
    end

    test "active scope excludes expired sessions" do
      old_session = Shakha::Session.create!(user: @user, client: @client)
      old_session.update!(created_at: 60.days.ago)

      active_session = Shakha::Session.create!(user: @user, client: @client)

      assert_includes Shakha::Session.active, active_session
      refute_includes Shakha::Session.active, old_session
    end

    test "expires_at returns correct time" do
      session = Shakha::Session.create!(user: @user, client: @client)
      expected = session.created_at + Shakha.config.session_lifetime
      assert_in_delta expected, session.expires_at, 1.second
    end

    test "expired? returns true for old sessions" do
      session = Shakha::Session.create!(user: @user, client: @client)
      session.update!(created_at: 60.days.ago)
      assert session.expired?
    end
  end
end
