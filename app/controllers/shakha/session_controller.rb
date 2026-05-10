# frozen_string_literal: true

module Shakha
  class SessionController < ApplicationController
    skip_before_action :verify_authenticity_token, only: [:check]

    def show
      render json: {
        user_id: current_user&.pairwise_sub,
        email: current_user&.email,
        name: current_user&.name,
        expires_at: current_session&.expires_at&.iso8601
      }
    end

    def check
      if signed_in?
        render json: { status: "active" }
      else
        render json: {
          status: "login_required",
          reason: "no_session"
        }, status: :unauthorized
      end
    end

    def destroy
      current_session&.destroy
      cookies.delete(:shakha_session_token)
      render json: { status: "signed_out" }
    end
  end
end