# API seam

## Implemented now

`GET /health` returns HTTP 200 JSON:

```json
{"status": "ok", "service": "flowdo"}
```

This is liveness only; it does not connect to or test a database. `/api` is a
registered Blueprint with no public endpoints yet. Unknown routes return JSON
404; unsupported methods return 405 preserving Allow; internal failures return
a generic 500. No accounts or API tokens exist.

## Later accounts milestone (design only)

| Method | Path | Purpose |
| --- | --- | --- |
| POST | /api/tokens | Exchange credentials for a revocable expiring token |
| DELETE | /api/tokens | Revoke caller's token |
| GET | /api/me | Authenticated user's own account |
| GET | /api/current-task | Own current intention, or null when absent |
| PUT | /api/current-task | Set or change the one current intention |
| DELETE | /api/current-task | Clear the current intention |
| POST | /api/current-task/complete | Complete the current intention |

Native requests will use Bearer tokens over HTTPS, independently of browser
session cookies. Ownership derives from the authenticated user, never a supplied
user_id. Passwords use Werkzeug hashing; credentials on Mac use Keychain.

Future response shape:

```json
{
  "id": "35b35bd6-a948-4acb-85b6-e6e95be44451",
  "title": "Prepare TAC slides",
  "started_at": "2026-09-19T20:00:00Z",
  "completed_at": null,
  "updated_at": "2026-09-19T20:00:00Z"
}
```

Before sync, finalize conflict/tombstone behavior, idempotent retry handling,
validation, UTC timestamp precision and authorization tests. Local Swift Codable
files are an internal format; a future API DTO must explicitly map snake_case
and ISO-8601 dates instead of uploading that file directly.
