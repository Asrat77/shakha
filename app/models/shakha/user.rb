# frozen_string_literal: true

module Shakha
  class User < ::ApplicationRecord
    self.table_name = "shakha_users"

    has_many :sessions, class_name: "Shakha::Session", dependent: :destroy

    validates :provider, presence: true
    validates :uid, presence: true
    validates :uid, uniqueness: { scope: :provider }
  end
end
