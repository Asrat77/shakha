# frozen_string_literal: true

module Shakha
  class Client < ::ApplicationRecord
    self.table_name = "shakha_clients"

    has_many :sessions, class_name: "Shakha::Session", dependent: :restrict_with_error
    has_many :users, class_name: "Shakha::User", dependent: :nullify

    validates :origin, presence: true, uniqueness: true

    def self.find_by_origin!(origin)
      find_by!(origin: URI.parse(origin).origin)
    end
  end
end