Rails.application.routes.draw do
  mount Shakha::Engine => "/auth/shakha"

  get "/me", to: "me#show", defaults: { format: :json }
end
