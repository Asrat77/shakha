# frozen_string_literal: true

module Shakha
  class Session < ::ApplicationRecord
    self.table_name = "shakha_sessions"

    belongs_to :user, class_name: "Shakha::User", optional: true

    before_create :generate_token

    scope :active, -> { where("created_at > ?", Shakha.config.session_lifetime.ago) }

    EXCHANGE_CODE_TTL = 60.seconds

    def expired?
      created_at < Shakha.config.session_lifetime.ago
    end

    def expires_at
      created_at + Shakha.config.session_lifetime
    end

    # Issues a short-lived, single-use code the frontend swaps for the session
    # token, so the token itself never travels in a redirect URL.
    def generate_exchange_code!
      update_columns(
        exchange_code: SecureRandom.urlsafe_base64(32),
        exchange_code_expires_at: EXCHANGE_CODE_TTL.from_now
      )
      exchange_code
    end

    # Redeems a code for its session, atomically clearing it so a code can be
    # used at most once even under concurrent requests.
    def self.exchange(code)
      return nil if code.blank?

      session = active.where(exchange_code: code)
                      .where("exchange_code_expires_at > ?", Time.current).first
      return nil unless session

      claimed = where(id: session.id).where.not(exchange_code: nil)
                .update_all(exchange_code: nil, exchange_code_expires_at: nil)
      claimed == 1 ? session : nil
    end

    private

    def generate_token
      self.token ||= SecureRandom.urlsafe_base64(32)
    end
  end
end
