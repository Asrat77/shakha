# frozen_string_literal: true

module Shakha
  class SessionController < ApplicationController
    skip_before_action :verify_authenticity_token, only: [:check]

    def index
      return render json: { error: "Authentication required" }, status: :unauthorized unless signed_in?

      sessions = current_user.sessions.active.order(created_at: :desc)

      render json: {
        current_token: current_session.token,
        sessions: sessions.map { |s|
          {
            id: s.id,
            token: s.token,
            created_at: s.created_at.iso8601,
            expires_at: s.expires_at.iso8601,
            current: s.token == current_session.token
          }
        }
      }
    end

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

      respond_to do |format|
        format.html { redirect_to params[:return_to].presence || "/" }
        format.json { render json: { status: "signed_out" } }
      end
    end

    def revoke
      return render json: { error: "Authentication required" }, status: :unauthorized unless signed_in?

      session = current_user.sessions.find(params[:id])
      session.destroy

      cookies.delete(:shakha_session_token) if session.token == current_session&.token

      ActiveSupport::Notifications.instrument("shakha.session_revoked", {
        session_id: session.id,
        user_id: current_user.id,
        ip: request.remote_ip
      })

      render json: { status: "revoked" }
    end
  end
end