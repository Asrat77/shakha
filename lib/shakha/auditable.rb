# frozen_string_literal: true

module Shakha
  module Auditable
    extend ActiveSupport::Concern

    included do
      after_action :log_sign_in, only: [:callback]
      after_action :log_sign_out, only: [:destroy]
      after_action :log_token_exchange, only: [:token]
    end

    private

    def log_sign_in
      return unless response.successful? && @current_user

      ActiveSupport::Notifications.instrument("shakha.sign_in", {
        user_id: @current_user&.id,
        pairwise_sub: @current_user&.pairwise_sub,
        client_id: @current_client&.id,
        ip: request.remote_ip,
        user_agent: request.user_agent
      })
    end

    def log_sign_out
      return unless action_name == "destroy"

      ActiveSupport::Notifications.instrument("shakha.sign_out", {
        session_id: @current_session&.id,
        user_id: @current_session&.user_id,
        ip: request.remote_ip
      })
    end

    def log_token_exchange
      return unless action_name == "token"

      ActiveSupport::Notifications.instrument("shakha.token_exchange", {
        ip: request.remote_ip,
        user_agent: request.user_agent,
        success: response.successful?
      })
    end
  end
end
