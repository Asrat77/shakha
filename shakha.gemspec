# frozen_string_literal: true

# Read version without loading the full engine
VERSION = File.read(File.expand_path("lib/shakha/version.rb", __dir__)).match(/VERSION\s*=\s*["']([^"']+)["']/)[1]

Gem::Specification.new do |spec|
  spec.name = "shakha"
  spec.version = VERSION
  spec.authors = ["Asrat"]
  spec.email = ["asrat@example.com"]

  spec.summary = "Headless Google OAuth broker with PKCE, pairwise subjects, and zero JavaScript"
  spec.description = <<~DESC
    Shakha is a headless authentication broker gem for Rails that handles Google OAuth 2.0
    with PKCE security. It provides domain-scoped user identifiers via pairwise subjects,
    ensuring the same Google account gets different IDs across different applications.

    Built DHH-style: database sessions (no Redis), Turbo native (zero JS), and a single
    "Continue with Google" button. Works as an embedded Rails engine or standalone service.
  DESC
  spec.homepage = "https://shakha.dev"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["homepage_uri"] = spec.homepage

  spec.files = Dir["lib/**/*", "app/**/*"]
  spec.files += Dir["*.md", "LICENSE*"]

  spec.add_dependency "jwt", "~> 2.7"
  spec.add_dependency "activesupport", ">= 7.1", "< 10"
  spec.add_dependency "railties", ">= 7.1", "< 10"
end