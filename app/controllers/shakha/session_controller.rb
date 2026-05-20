# frozen_string_literal: true

module Shakha
  class SessionController < ApplicationController
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
