Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("ALLOWED_REDIRECT_ORIGINS", "http://localhost:5173").split(",")

    resource "*",
      headers: :any,
      methods: %i[get post delete options head]
  end
end
