# frozen_string_literal: true

module Shakha
  class Session < ::ApplicationRecord
    self.table_name = "shakha_sessions"

    belongs_to :user, class_name: "Shakha::User", optional: true
    belongs_to :client, class_name: "Shakha::Client"

    before_create :generate_token
    before_create :generate_jti

    scope :active, -> { where("created_at > ?", Shakha.config.session_lifetime.ago) }

    def expired?
      created_at < Shakha.config.session_lifetime.ago
    end

    def expires_at
      created_at + Shakha.config.session_lifetime
    end

    private

    def generate_token
      self.token ||= SecureRandom.urlsafe_base64(32)
    end

    def generate_jti
      self.jti ||= SecureRandom.uuid
    end
  end
end