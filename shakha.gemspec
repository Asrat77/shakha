# frozen_string_literal: true

# Read version without loading the full engine
VERSION = File.read(File.expand_path("lib/shakha/version.rb", __dir__)).match(/VERSION\s*=\s*["']([^"']+)["']/)[1]

Gem::Specification.new do |spec|
  spec.name = "shakha"
  spec.version = VERSION
  spec.authors = [ "Asrat" ]
  spec.email = [ "asratextras77@gmail.com" ]

  spec.summary = "SPA-first OAuth session broker for Rails — one redirect, one token, done"
  spec.description = <<~DESC
    Shakha is a headless OAuth broker engine for Rails APIs and monoliths.
    Your frontend does a single redirect; Shakha runs the OAuth dance
    (PKCE, state) against Google or GitHub, stores a revocable
    database-backed session, and redirects back with a session token usable
    via encrypted cookie or Authorization: Bearer. No JWTs issued, no Redis,
    no frontend SDK. Pre-1.0: APIs and security posture still evolving.
  DESC
  spec.homepage = "https://github.com/Asrat77/shakha"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*", "app/**/*", "README.md", "LICENSE.txt"]

  spec.add_dependency "jwt", "~> 2.7"
  spec.add_dependency "activesupport", ">= 7.1", "< 10"
  spec.add_dependency "railties", ">= 7.1", "< 10"
end
