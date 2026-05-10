# frozen_string_literal: true

require_relative "lib/shakha"

Gem::Specification.new do |spec|
  spec.name = "shakha"
  spec.version = Shakha::VERSION
  spec.authors = ["Shakha Authors"]
  spec.email = ["contact@shakha.dev"]

  spec.summary = "Minimal auth broker for Google OAuth with PKCE and pairwise subjects"
  spec.description = <<~DESC
    Shakha handles Google OAuth + PKCE and gives your app a domain-scoped identity (pairwise_sub)
    and a signed id_token. No client signup. No unnecessary scopes. Just identity.
  DESC
  spec.homepage = "https://shakha.dev"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/shakha/shakha"

  spec.files = Dir["{lib,app,config}/**/*", "*.md"]
  spec.files += Dir["generators/**/*"]

  spec.add_dependency "rails", ">= 7.1"
  spec.add_dependency "jwt", "~> 2.7"
  spec.add_dependency "pundit", "~> 2.3"
  spec.add_dependency "rack-attack", "~> 6.7"

  spec.add_development_dependency "sqlite3"
  spec.add_development_dependency "minitest", "~> 5.21"
  spec.add_development_dependency "railties", ">= 7.1"
end