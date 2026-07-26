# frozen_string_literal: true

require_relative "../test_helper"

module Shakha
  class UserTest < ActiveSupport::TestCase
    test "requires provider and uid" do
      user = Shakha::User.new(client: create_client)
      refute user.valid?
      assert user.errors[:provider].any?
      assert user.errors[:uid].any?
    end

    test "uid is unique per provider" do
      create_user(provider: "google", uid: "dup")
      dup = Shakha::User.new(client: create_client, provider: "google", uid: "dup")
      refute dup.valid?

      other_provider = Shakha::User.new(client: create_client, provider: "github", uid: "dup")
      assert other_provider.valid?
    end

    test "destroying a user destroys its sessions" do
      user = create_user
      create_session_record(user: user)
      assert_difference -> { Shakha::Session.count }, -1 do
        user.destroy
      end
    end
  end
end
