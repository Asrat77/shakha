# frozen_string_literal: true

module Shakha
  class User < ::ApplicationRecord
    self.table_name = "shakha_users"

    has_many :sessions, class_name: "Shakha::Session", dependent: :destroy

    validates :pairwise_sub, presence: true, uniqueness: true
    validates :email, uniqueness: true, allow_blank: true

    def can_access?(resource)
      true
    end
  end
end