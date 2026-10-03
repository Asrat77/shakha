# frozen_string_literal: true

require_relative "../test_helper"

module Shakha
  class SessionsEndpointsTest < ActionDispatch::IntegrationTest
    setup do
      @user = create_user
      @current = Shakha::Session.create!(user: @user, ip_address: "10.0.0.1", user_agent: "Laptop")
      @other_device = Shakha::Session.create!(user: @user, ip_address: "10.0.0.2", user_agent: "Phone",
                                              created_at: 1.day.ago)
    end

    test "listing sessions requires auth" do
      get "/auth/shakha/sessions"
      assert_response :unauthorized
    end

    test "lists the current user's active sessions newest first, flagging the current one" do
      Shakha::Session.create!(user: @user, created_at: (Shakha.config.session_lifetime + 1.day).ago)
      create_session_record(user: create_user(uid: "someone_else"))

      get "/auth/shakha/sessions", headers: bearer(@current)
      assert_response :success

      sessions = JSON.parse(response.body)["sessions"]
      assert_equal [ @current.id, @other_device.id ], sessions.map { |s| s["id"] }
      assert_equal [ true, false ], sessions.map { |s| s["current"] }
      assert_equal "10.0.0.2", sessions.last["ip_address"]
      assert_equal "Phone", sessions.last["user_agent"]
      assert sessions.first["created_at"].present?
    end

    test "revokes one of your own sessions" do
      delete "/auth/shakha/sessions/#{@other_device.id}", headers: bearer(@current)
      assert_response :success
      assert_nil Shakha::Session.find_by(id: @other_device.id)

      get "/auth/shakha/session", headers: bearer(@other_device)
      assert_response :unauthorized
      get "/auth/shakha/session", headers: bearer(@current)
      assert_response :success
    end

    test "can revoke the current session" do
      delete "/auth/shakha/sessions/#{@current.id}", headers: bearer(@current)
      assert_response :success

      get "/auth/shakha/session", headers: bearer(@current)
      assert_response :unauthorized
    end

    test "cannot revoke another user's session" do
      stranger_session = create_session_record(user: create_user(uid: "someone_else"))

      delete "/auth/shakha/sessions/#{stranger_session.id}", headers: bearer(@current)
      assert_response :not_found
      assert Shakha::Session.exists?(stranger_session.id)
    end

    test "revoking requires auth" do
      delete "/auth/shakha/sessions/#{@other_device.id}"
      assert_response :unauthorized
      assert Shakha::Session.exists?(@other_device.id)
    end

    private

    def bearer(session_record)
      { "Authorization" => "Bearer #{session_record.token}" }
    end
  end
end
