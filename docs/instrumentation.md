# Instrumentation

Shakha emits [`ActiveSupport::Notifications`](https://api.rubyonrails.org/classes/ActiveSupport/Notifications.html)
events for the moments a host app usually wants to audit. Shakha doesn't log
or store them itself; subscribe and do whatever your app needs.

## Events

| Event | When | Payload |
|---|---|---|
| `shakha.sign_in` | After a successful OAuth callback creates a session | `user_id`, `provider` (Symbol, e.g. `:google`), `ip` |
| `shakha.auth_failure` | When the callback fails (bad `state`, missing PKCE cookie, provider error, ID-token check) | `provider` (Symbol), `error` (exception class name, e.g. `"Shakha::PKCEError"`) |
| `shakha.sign_out` | When `DELETE /sign_out` destroys a session. Not emitted if the request had no session. | `user_id` |

Payloads never include session tokens, exchange codes, or provider access tokens.

## Example: an audit log

```ruby
# config/initializers/shakha_audit.rb
ActiveSupport::Notifications.subscribe("shakha.sign_in") do |event|
  AuditLog.create!(action: "sign_in", **event.payload)
end

ActiveSupport::Notifications.subscribe("shakha.auth_failure") do |event|
  Rails.logger.warn("[shakha] auth failure: #{event.payload.inspect}")
end
```

Subscribe to every Shakha event at once with a regex:

```ruby
ActiveSupport::Notifications.subscribe(/\Ashakha\./) do |event|
  Rails.logger.info("[#{event.name}] #{event.payload.inspect}")
end
```
