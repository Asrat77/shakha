# frozen_string_literal: true

require_relative "../test_helper"

module Shakha
  class UserTest < ActiveSupport::TestCase
    setup do
      @client = Shakha::Client.create!(origin: "https://test.com", name: "Test")
    end

    test "validates presence of provider" do
      user = Shakha::User.new(uid: "123", client: @client)
      refute user.valid?
      assert_includes user.errors[:provider], "can't be blank"
    end

    test "validates presence of uid" do
      user = Shakha::User.new(provider: "google", client: @client)
      refute user.valid?
      assert_includes user.errors[:uid], "can't be blank"
    end

    test "validates uniqueness of uid scoped to provider" do
      Shakha::User.create!(provider: "google", uid: "123", client: @client)
      user = Shakha::User.new(provider: "google", uid: "123", client: @client)
      refute user.valid?
      assert_includes user.errors[:uid], "has already been taken"
    end

    test "allows same uid with different provider" do
      Shakha::User.create!(provider: "google", uid: "123", client: @client)
      user = Shakha::User.new(provider: "github", uid: "123", client: @client)
      assert user.valid?
    end

    test "allows blank email" do
      user = Shakha::User.new(provider: "google", uid: "test123", client: @client)
      assert user.valid?
    end
  end
end
