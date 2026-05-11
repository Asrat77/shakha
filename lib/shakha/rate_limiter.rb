# frozen_string_literal: true

module Shakha
  module RateLimiter
    extend ActiveSupport::Concern

    included do
      before_action :check_rate_limit_authorize, only: [:authorize]
      before_action :check_rate_limit_token, only: [:token]
    end

    private

    def check_rate_limit_authorize
      check_rate_limit("authorize", max: 20, period: 1.minute)
    end

    def check_rate_limit_token
      check_rate_limit("token", max: 10, period: 1.minute)
    end

    def check_rate_limit(key, max:, period:)
      return unless Shakha.config.rate_limiting_enabled

      cache_key = "shakha-rate:#{key}:#{request.remote_ip}"

      count = Rails.cache.read(cache_key).to_i + 1

      if count == 1
        Rails.cache.write(cache_key, count, expires_in: period.seconds)
      elsif count > max
        render json: { error: "Too many requests. Try again later." }, status: :too_many_requests
        return
      else
        Rails.cache.write(cache_key, count, expires_in: period.seconds)
      end
    end
  end
end
