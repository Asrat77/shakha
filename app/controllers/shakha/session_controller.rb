# frozen_string_literal: true

module Shakha
  class SessionController < ApplicationController
    skip_before_action :verify_authenticity_token, only: :exchange

    # POST /session/exchange — swap a one-time code for the session token.
    def exchange
      session_record = Shakha::Session.exchange(params[:code])
      if session_record
        render json: { token: session_record.token,
                       expires_at: session_record.expires_at.iso8601 }
      else
        render json: { error: "Invalid or expired code" }, status: :unauthorized
      end
    end

    def show
      unless signed_in?
        return render json: { error: "Authentication required" }, status: :unauthorized
      end

      render json: {
        user: {
          id: current_user.id,
          email: current_user.email,
          name: current_user.name,
          picture: current_user.picture,
          provider: current_user.provider
        },
        session: {
          expires_at: current_session.expires_at.iso8601
        }
      }
    end

    def check
      if signed_in?
        render json: { status: "active" }
      else
        render json: { status: "expired" }, status: :unauthorized
      end
    end
  end
end
