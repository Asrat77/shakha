# frozen_string_literal: true

require_relative "../test_helper"

module Shakha
  class UserTest < ActiveSupport::TestCase
    fixtures :shakha_users, :shakha_clients

    setup do
      @client = shakha_clients(:one)
    end

    test "validates presence of pairwise_sub" do
      user = Shakha::User.new(client: @client)
      refute user.valid?
      assert_includes user.errors[:pairwise_sub], "can't be blank"
    end

    test "validates uniqueness of pairwise_sub" do
      existing = shakha_users(:one)
      user = Shakha::User.new(pairwise_sub: existing.pairwise_sub, client: @client)

      refute user.valid?
      assert_includes user.errors[:pairwise_sub], "has already been taken"
    end

    test "validates uniqueness of email when present" do
      existing = shakha_users(:one)
      existing.update!(email: "test@example.com")

      user = Shakha::User.new(
        pairwise_sub: "ps_unique123",
        email: "test@example.com",
        client: @client
      )

      refute user.valid?
      assert_includes user.errors[:email], "has already been taken"
    end

    test "allows blank email" do
      user = Shakha::User.new(
        pairwise_sub: "ps_test123",
        email: nil,
        client: @client
      )

      assert user.valid?
    end
  end
end