# Phase 1: Security Fixes (SPA-Updated)

Fix 3 security issues. JWT revocation (#1 from original) is removed since we no longer use JWTs.

---

## Security #1: PKCE Cookie Must Be Encrypted

**File**: `lib/shakha/pkce.rb:43-48`
**Severity**: 🟡 Medium

The PKCE cookie stores the `code_verifier` in plain JSON. If leaked before the OAuth flow completes, an attacker can exchange the authorization code for tokens.

### The fix:
```ruby
# Store (encrypted)
cookies.encrypted[PKCE_COOKIE_NAME] = {
  value: pkce_record.merge(state: state).to_json,
  httponly: true,
  secure: Rails.env.production?,
  same_site: :lax,
  expires: Time.now.utc + PKCE_COOKIE_EXPIRY_SECONDS
}

# Read (encrypted)
pkce_json = cookies.encrypted[PKCE_COOKIE_NAME]
```

---

## Security #2: State Parameter Must Use Timing-Safe Comparison

**File**: `lib/shakha/pkce.rb:69`
**Severity**: 🟡 Medium

```ruby
# Before — vulnerable to timing attacks
raise PKCEError, "State mismatch" unless stored_state == state_param

# After — timing-safe
raise PKCEError, "State mismatch" unless ActiveSupport::SecurityUtils.secure_compare(stored_state, state_param)
```

---

## Security #3: No `nonce` in OIDC Flow (Google)

**File**: `app/controllers/shakha/auth_controller.rb` → `lib/shakha/providers/google.rb`
**Severity**: 🟠 High — ID token replay possible without nonce verification

### The fix:
The Google provider already includes `nonce` in the authorization URL (Phase 3 plan). Add nonce verification:

1. Store nonce in PKCE cookie alongside verifier and state
2. After Google callback, verify `id_token["nonce"]` matches stored nonce

```ruby
# In PKCEMixin#create_pkce_bundle:
nonce = SecureRandom.urlsafe_base64(32)
pkce_record = { verifier: verifier, return_to: return_to, nonce: nonce }

# In GoogleProvider#identity_from_response:
def identity_from_response(token_response, expected_nonce: nil)
  id_token = token_response["id_token"]
  raise OAuthError, "No id_token received" unless id_token

  payload = JWT.decode(id_token, nil, false)[0]

  if expected_nonce && payload["nonce"] != expected_nonce
    raise OAuthError, "Nonce mismatch"
  end

  # ... rest of identity extraction
end
```

---

## Security #4: Return-To URL Validation

**File**: `app/controllers/shakha/auth_controller.rb`
**Severity**: 🟠 High — Open redirect vulnerability

The SPA flow redirects the user to `return_to` with the session token in the URL. An attacker could craft `return_to=https://evil.com` to steal tokens.

### The fix:
Validate `return_to` against a whitelist or same-origin check:

```ruby
def sanitize_return_to(raw)
  return "/" if raw.blank?

  uri = URI.parse(raw)
  app_origin = URI.parse(Shakha.config.app_origin)

  # Must be same origin as the Rails app OR in allowed redirect origins
  unless uri.host == app_origin.host || allowed_redirect_origin?(uri.origin)
    return "/"
  end

  raw
rescue URI::InvalidURIError
  "/"
end

def allowed_redirect_origin?(origin)
  Shakha.config.allowed_redirect_origins&.include?(origin)
end
```

Add to config:
```ruby
config.allowed_redirect_origins = ENV.fetch("ALLOWED_REDIRECT_ORIGINS", "").split(",")
```

For SPAs: set `ALLOWED_REDIRECT_ORIGINS=https://app.yourapp.com` so the token redirect to the React app is allowed.

---

## Security #5: Session Token Entropy

**File**: `app/models/shakha/session.rb:26`
**Severity**: 🟡 Low — 32 bytes of urlsafe_base64 is fine but document it

```ruby
def generate_token
  self.token ||= SecureRandom.urlsafe_base64(32)  # 256 bits of entropy
end
```

This produces ~43 character tokens with 256 bits of entropy. Sufficient for session tokens. The token is passed in URLs (for SPA redirect) and stored in cookies. Consider if token exposure in URL (even briefly during redirect) is acceptable for your threat model.

Alternative: use a one-time exchange code for the redirect, then have the SPA call `/auth/shakha/session/exchange` to get the actual session token. This is more secure but adds complexity. Start with token-in-URL, document the tradeoff.

---

## What We DON'T Need to Fix

- **JWT Revocation**: Session tokens are random strings stored in DB. Deleting the row = revoked. No JWT = no revocation problem.
- **JWKS Exposure**: No JWKS endpoint to expose.
