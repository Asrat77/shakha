# Example: Rails API + React

The smallest complete Shakha setup: a Rails API (`api/`) with one protected
endpoint, and a Vite + React frontend (`web/`) that signs in with Google,
swaps the one-time code for a session token, and calls the API with
`Authorization: Bearer`.

```
api/   Rails 8.1 API-only app, SQLite. Shakha mounted at /auth/shakha, GET /me protected.
web/   Vite + React. Sign-in button, /login return page, sign-out button.
```

The API uses the Shakha checkout two directories up
(`gem "shakha", path: "../../.."`), so this example always runs against the
code in this repo.

## 1. Create Google OAuth credentials

In the [Google Cloud console](https://console.cloud.google.com/apis/credentials),
create an **OAuth client ID** of type **Web application** and add this
**Authorized redirect URI**:

```
http://localhost:3000/auth/shakha/google/callback
```

That's the API's callback, not the React app's. Shakha handles the callback
and then redirects to the React app.

## 2. Run the API

```bash
cd api
bundle install
bin/rails db:prepare
GOOGLE_CLIENT_ID=... GOOGLE_CLIENT_SECRET=... bin/rails s
```

| Variable | Default | Purpose |
|---|---|---|
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | — | From step 1 |
| `APP_ORIGIN` | `http://localhost:3000` | The API's origin, used to build the callback URL |
| `ALLOWED_REDIRECT_ORIGINS` | `http://localhost:5173` | Origins allowed as `return_to` and for CORS |

## 3. Run the frontend

```bash
cd web
npm install
npm run dev
```

Set `VITE_API_URL` if the API isn't on `http://localhost:3000`.

## What you should see

1. Open http://localhost:5173 and click **Sign in with Google**.
2. The browser goes to `localhost:3000/auth/shakha/google`, then to Google's
   consent screen.
3. Google sends you back to the API, which creates your user and session and
   redirects to `localhost:5173/login?code=...`.
4. The React app POSTs the code to `/auth/shakha/session/exchange`, stores the
   returned token in `localStorage`, and calls `GET /me`.
5. You see "Signed in as ..." with your profile JSON. Reloading keeps you
   signed in; **Sign out** calls `DELETE /auth/shakha/sign_out` and clears the
   token.

Without a token, `GET /me` returns `401 {"error":"Authentication required"}`.

## Where the Shakha parts are

- `api/config/routes.rb`: mounts the engine and defines `GET /me` (JSON by default, so
  `authenticate!` answers 401 instead of redirecting).
- `api/app/controllers/me_controller.rb`: `before_action :authenticate!` and
  `current_user`.
- `api/config/initializers/shakha.rb`: written by `bin/rails generate shakha:install`.
- `api/config/initializers/cors.rb`: lets the React origin call the API.
- `web/src/App.jsx`: the whole frontend flow in one component.
