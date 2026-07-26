# Security Policy

## Supported versions

Shakha is pre-1.0. Security fixes are released only for the latest minor
version. Please stay current until 1.0 establishes a support window.

## Reporting a vulnerability

**Do not open a public issue for security problems.**

Report privately through GitHub Security Advisories — the "Report a
vulnerability" button on the repository's Security tab. Include a description,
affected versions, and a reproduction if you have one. We aim to acknowledge
within 7 days and to coordinate disclosure once a fix is available.

## Threat model

Shakha is an OAuth session broker. It is responsible for the integrity of the
OAuth redirect flow and for session lifecycle; it deliberately delegates the
rest to the host application.

### What Shakha protects

- **Authorization-code interception** — PKCE (S256) on every flow.
- **CSRF on the OAuth round-trip** — a random `state`, stored in an encrypted,
  http-only cookie and compared timing-safely on callback.
- **ID token replay / substitution (Google)** — the OIDC `nonce` is verified
  against the value minted at authorize time, and the `iss`, `aud`, and `exp`
  claims are validated. The `aud` check rejects tokens minted for other clients.
- **Open redirects** — `return_to` is validated against the app origin and an
  explicit `allowed_redirect_origins` allowlist before it is stored, so the
  post-login redirect can only reach approved origins.
- **Token exposure in URLs** — by default the callback redirects with a
  single-use, 60-second exchange code rather than the session token itself; the
  frontend swaps it for the token over a POST.
- **Session revocation** — sessions are random tokens stored in the database;
  deleting the row revokes access immediately. No JWTs are issued, so there is
  no standalone-token revocation gap.
- **Brute force on the auth endpoints** — optional rate limiting on `authorize`
  and `callback`.

### What the host application owns

- **TLS** — Shakha assumes it runs behind HTTPS in production; the Google ID
  token's signature is trusted on the basis of the TLS connection to Google's
  token endpoint rather than re-verified.
- **CORS** — the host configures which origins may call its API.
- **Frontend XSS** — any script that runs in the frontend can read a bearer
  token the SPA stores; Shakha cannot defend a compromised frontend.
- **Secret management** — `GOOGLE_CLIENT_SECRET`, `GITHUB_CLIENT_SECRET`, and
  the Rails `secret_key_base` (which encrypts Shakha's cookies) are the host's
  responsibility.
- **Rate-limit backing store** — atomic rate limiting requires a shared,
  atomic cache (Redis/Memcached) in multi-process deployments; the default
  in-memory store does not coordinate across processes.
