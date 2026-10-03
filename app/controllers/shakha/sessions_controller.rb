# frozen_string_literal: true

module Shakha
  class SessionsController < ApplicationController
    before_action :authenticate!

    # GET /sessions — the current user's active sessions, newest first.
    def index
      sessions = Shakha::Session.for(current_user).map do |session_record|
        {
          id: session_record.id,
          ip_address: session_record.ip_address,
          user_agent: session_record.user_agent,
          created_at: session_record.created_at.iso8601,
          current: session_record.id == current_session.id
        }
      end

      render json: { sessions: sessions }
    end

    # DELETE /sessions/:id — revoke one of the current user's sessions.
    def destroy
      session_record = Shakha::Session.for(current_user).find_by(id: params[:id])
      return render json: { error: "Session not found" }, status: :not_found unless session_record

      session_record.destroy
      cookies.delete(:shakha_session_token) if session_record.id == current_session.id

      render json: { status: "revoked" }
    end
  end
end
