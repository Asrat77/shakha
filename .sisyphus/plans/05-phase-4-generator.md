# Phase 4: `rails generate shakha:install`

One command. Google + GitHub sign-in. Works with Rails API + React or Rails monolith.

## Generator

**File**: `lib/generators/shakha/install/install_generator.rb`

```ruby
module Shakha
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration
      source_root File.expand_path("templates", __dir__)

      desc "Installs Shakha — headless OAuth broker for Rails"

      def copy_migration
        migration_template "create_shakha_tables.rb.erb", "db/migrate/create_shakha_tables.rb"
      end

      def copy_initializer
        template "shakha.rb.erb", "config/initializers/shakha.rb"
      end

      def inject_application_controller
        path = "app/controllers/application_controller.rb"
        return unless File.exist?(path)

        content = File.read(path)
        return if content.include?("Shakha::ControllerHelpers")

        inject_into_class path, "ApplicationController", "  include Shakha::ControllerHelpers\n"
        say_status :insert, "ApplicationController → include Shakha::ControllerHelpers", :green
      end

      def print_post_install
        say "\n  Shakha installed!", :green
        say "  ──────────────────────────────────", :green
        say ""
        say "  1. Set environment variables:", :yellow
        say "     GOOGLE_CLIENT_ID", :cyan
        say "     GOOGLE_CLIENT_SECRET", :cyan
        say ""
        say "  2. (Optional) GitHub auth:", :yellow
        say "     GITHUB_CLIENT_ID", :cyan
        say "     GITHUB_CLIENT_SECRET", :cyan
        say ""
        say "  3. For SPA (React/Vue):", :yellow
        say "     ALLOWED_REDIRECT_ORIGINS=https://your-frontend.com", :cyan
        say ""
        say "  4. Run migrations:", :yellow
        say "     bin/rails db:migrate", :cyan
        say ""
        say "  5. Google redirect URI:", :yellow
        say "     #{Shakha.config.app_origin}/auth/shakha/google/callback", :cyan
        say "  ──────────────────────────────────", :green
        say ""
        say "  Tell your frontend dev:", :cyan
        say '    Sign in:  <a href="#{Shakha.config.app_origin}/auth/shakha/google">'
        say "    Session:  GET #{Shakha.config.app_origin}/auth/shakha/session"
        say "    Auth:     Authorization: Bearer <token>"
        say "    Sign out: DELETE #{Shakha.config.app_origin}/auth/shakha/sign_out"
      end

      private

      def migration_version
        "[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
      end

      def app_origin
        "http://localhost:3000"
      end
    end
  end
end
```

## Migration Template

**File**: `lib/generators/shakha/install/templates/create_shakha_tables.rb.erb`

```ruby
class CreateShakhaTables < ActiveRecord::Migration<%= migration_version %>
  def change
    create_table :shakha_clients do |t|
      t.string :name, null: false
      t.string :origin, null: false
      t.timestamps
      t.index :origin, unique: true
    end

    create_table :shakha_users do |t|
      t.references :client, null: false, foreign_key: { to_table: :shakha_clients }
      t.string :provider, null: false
      t.string :uid, null: false
      t.string :email
      t.string :name
      t.string :picture
      t.timestamps
      t.index [:provider, :uid], unique: true
      t.index :email
    end

    create_table :shakha_sessions do |t|
      t.references :user, foreign_key: { to_table: :shakha_users }
      t.references :client, null: false, foreign_key: { to_table: :shakha_clients }
      t.string :token, null: false
      t.string :ip_address
      t.string :user_agent
      t.timestamps
      t.index :token, unique: true
      t.index :created_at
    end
  end
end
```

## Initializer Template

**File**: `lib/generators/shakha/install/templates/shakha.rb.erb`

```ruby
Shakha.setup do |config|
  # Your Rails app's origin
  config.app_origin = ENV.fetch("APP_ORIGIN", "http://localhost:3000")

  # Allowed frontend origins for SPA token redirect
  config.allowed_redirect_origins = ENV.fetch("ALLOWED_REDIRECT_ORIGINS", "").split(",")

  # Google OAuth (required)
  config.google_client_id     = ENV["GOOGLE_CLIENT_ID"]
  config.google_client_secret = ENV["GOOGLE_CLIENT_SECRET"]

  # GitHub OAuth (optional — remove from providers if unused)
  config.github_client_id     = ENV["GITHUB_CLIENT_ID"]
  config.github_client_secret = ENV["GITHUB_CLIENT_SECRET"]

  # Enabled providers
  # config.providers = [:google]               # Google only
  config.providers = [:google, :github]         # Both

  # Session lifetime (default: 30 days)
  # config.session_lifetime = 30.days

  # Rate limiting (default: false)
  # config.rate_limiting_enabled = true
end
```
