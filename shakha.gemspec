# frozen_string_literal: true

# Read version without loading the full engine
VERSION = File.read(File.expand_path("lib/shakha/version.rb", __dir__)).match(/VERSION\s*=\s*["']([^"']+)["']/)[1]

Gem::Specification.new do |spec|
  spec.name = "shakha"
  spec.version = VERSION
  spec.authors = ["Asrat"]
  spec.email = ["asrat@example.com"]

  spec.summary = "Minimal auth broker for Google OAuth with PKCE and pairwise subjects"
  spec.description = <<~DESC
    Shakha handles Google OAuth + PKCE and gives your app a domain-scoped identity (pairwise_sub)
    and a signed id_token. No client signup. No unnecessary scopes. Just identity.
  DESC
  spec.homepage = "https://shakha.dev"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["homepage_uri"] = spec.homepage

  spec.files = Dir["lib/**/*", "app/**/*", "generators/**/*"]
  spec.files += Dir["*.md", "LICENSE*"]

  spec.add_dependency "jwt", "~> 2.7"
  spec.add_dependency "activesupport", ">= 7.1"
end