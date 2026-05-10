# frozen_string_literal: true

module Shakha
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      @env = env
      @request = ActionDispatch::Request.new(env)

      if verify_token_request?
        verify_token!
      else
        @app.call(env)
      end
    end

    private

    attr_reader :request

    def verify_token_request?
      request.path == "/auth/shakha/token" && request.post?
    end

    def verify_token!
      token = extract_token || raise(JWTError, "Missing token")
      payload = Shakha.verify_token(token)

      @env["shakha.user_id"] = payload[:pairwise_sub]
      @env["shakha.email"] = payload[:email]
      @env["shakha.name"] = payload[:name]

      @app.call(@env)
    rescue JWTError => e
      [401, { "Content-Type" => "application/json" }, [{ error: e.message }.to_json]]
    end

    def extract_token
      if request.content_type == "application/json"
        JSON.parse(request.body.read)["id_token"]
      elsif request.params["id_token"].present?
        request.params["id_token"]
      end
    end
  end
end