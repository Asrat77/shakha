# frozen_string_literal: true

module Shakha
  module Providers
    class Base
      def authorize_url(state:, code_challenge:, redirect_uri:)
        raise NotImplementedError
      end

      def exchange_code(code:, code_verifier:, redirect_uri:)
        raise NotImplementedError
      end

      def identity_from_response(token_response)
        raise NotImplementedError
      end

      def provider_name
        raise NotImplementedError
      end

      def scopes
        []
      end
    end
  end
end
