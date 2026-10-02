# DailyPlanner AI backend and sign-in setup

The code supports a private trial with you, your partner and a few friends. You have deployed `dailyplanner-ai` at `https://dailyplanner-ai.hahaj-dailyplanner.workers.dev` and configured your account. The backend error-handling updates are local until you deploy them. Codex did not run tests, builds, dependency installation, deployment, or live AI requests during this review.

The Qt app signs in directly with Supabase Auth. It sends a short-lived access token and the selected task/goal context to `POST /v1/breakdown` on a Cloudflare Worker. The Worker verifies the token, checks the account allowlist, validates the context, and reserves usage in one shared SQLite-backed Durable Object before calling Groq. Suggestions return to the existing editable preview. Only **Save subtasks** / **Save goal breakdown** writes them into local SQLite.

## What stays local

Tasks, descriptions, dates, goals, milestones, completion progress and settings continue using the existing `planner.db`. There is no planner database migration for this change and no cloud synchronization. The selected context is transmitted to Cloudflare and Groq when you request a breakdown; it is not stored by this backend.

Account records live in Supabase Auth. The quota object stores user UUIDs, request UUIDs, counters, expiration times and short concurrency leases. It does not store emails, passwords, access tokens, prompts, context or AI results. Expired quota metadata is removed during a subsequent accepted reservation. Cloudflare may retain storage backups under its platform retention rules. Application request/prompt logging is disabled.

Sign-in controls access to AI, not ownership of the local database. Different accounts using the same app working directory share that local planner. Each friend should run their own app installation with its own working directory. Account-specific local profiles and planner synchronization are deferred.

## 1. Configure Supabase Auth when ready

Use your existing Supabase project for DailyPlanner. These are manual setup instructions; they were not performed by Codex.

1. For the current private trial, enable email/password accounts and new-user signup, and disable **Confirm email**. Registration then returns a signed-in session without sending a verification email; the Qt signup handler already accepts that session. Set the minimum password length to 8 (or stronger). The native app accepts new passwords from 8 to 128 characters. Anonymous accounts are not supported. Unverified email addresses are account identifiers, not proof of email ownership; the backend's allowed-user list controls AI access.
2. Obtain the project URL (`https://PROJECT_REF.supabase.co`) and a **publishable** key starting with `sb_publishable_`. These are public app configuration. The Qt app intentionally does not accept legacy JWT-format anon keys. Do not use an `sb_secret_` key or a `service_role` key in the app or CMake settings.
3. Under Auth signing keys, use an active asymmetric **ES256** or **RS256** key. The backend validates signatures using `/auth/v1/.well-known/jwks.json` and checks issuer, audience, expiry, issue time, subject, role and anonymous status. Legacy HS256 signing is intentionally unsupported. After changing signing keys, sign out and sign in to obtain a new token.
4. Keep custom SMTP disabled for the current trial. Email confirmation, resend, and password recovery controls still exist in the Qt UI, but email delivery to friends requires a working custom SMTP provider. Do not use the recovery or verification controls for this no-email trial.
5. When enabling confirmation/recovery later, configure custom SMTP first, then change **Confirm signup** and **Reset password** email bodies to include the OTP variable `{{ .Token }}`. Supabase's built-in email delivery only sends to authorized project-team addresses. The app uses email codes, so no browser redirect, hosted password-reset website or mobile deep link is required for those flows.

Optional future **Confirm signup** body:

```html
<h2>Confirm your DailyPlanner account</h2>
<p>Enter this code in DailyPlanner:</p>
<p><strong>{{ .Token }}</strong></p>
<p>If you did not create an account, ignore this email.</p>
```

Optional future **Reset password** body:

```html
<h2>Reset your DailyPlanner password</h2>
<p>Enter this code and your new password in DailyPlanner:</p>
<p><strong>{{ .Token }}</strong></p>
<p>If you did not request this, ignore this email.</p>
```

The app calls Supabase's `signup`, `token`, `verify`, `resend`, `recover`, `user`, and `logout` REST endpoints. Passwords are sent over HTTPS to Supabase, not through the AI Worker. Existing Supabase account/email rate limits still apply. Native CAPTCHA integration, OAuth and MFA UI are outside this version; do not enable a CAPTCHA requirement without adding its client flow.

References: [email/password auth](https://supabase.com/docs/guides/auth/passwords), [custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp), [email templates](https://supabase.com/docs/guides/auth/auth-email-templates), [signing keys](https://supabase.com/docs/guides/auth/signing-keys).

## 2. Prepare the Worker locally

Use Node.js 22+ and npm. In PowerShell:

```powershell
Set-Location 'D:\Personal project\DailyPlanner\backend'
npm.cmd install
```

Keep the generated `package-lock.json` for repeatable installs; after reviewing it, commit it alongside the backend. Subsequent clean installs should use `npm.cmd ci`. The installed/pinned pair is Wrangler **4.147.0** with `@cloudflare/workers-types` **5.20261002.1**. The previous types v4 range conflicted with Wrangler's peer dependency. Dependency installation and validation are left for you to run.

Edit `wrangler.jsonc`:

- Choose a unique Worker `name` if `dailyplanner-ai` is unavailable.
- Replace `SUPABASE_URL` with your project URL.
- On a first deployment, keep `AI_ENABLED` as `"false"` until the Groq secret is configured. Your current configuration has it set to `"true"`; ordinary updates retain the existing secret and usage history.
- Set `ALLOWED_USER_IDS` to comma-separated Supabase **user UUIDs** for your trial accounts. Find them under **Authentication > Users** after account creation. An empty allowlist denies all AI access. Removing an ID and deploying the updated configuration revokes that account's backend access without changing the Groq key.
- Review the quota defaults below.

The current Wrangler configuration uses the documented `exports` declaration to create a SQLite-backed `QuotaGate` namespace. The package pins Wrangler 4.147.0. No remote migration/provisioning commands are required during preparation; the first actual deployment provisions the namespace. Do not replace the shared object name, class or binding during ordinary updates: that would create a new quota history.

Optional checks for you to run before deployment:

```powershell
npm.cmd run typecheck
npm.cmd run prepare-deploy
```

`prepare-deploy` is `wrangler deploy --dry-run`, which bundles locally into `dist` without publishing. These commands were not run during implementation. If your installed Wrangler does not recognize the documented `exports` field, update Wrangler before proceeding; do not silently deploy without the quota binding.

For a local Worker, copy `.dev.vars.example` to `.dev.vars` and fill it privately. `.dev.vars` is Git-ignored. The local file needs your real Groq key, Supabase project URL, approved user UUIDs and `AI_ENABLED=true`. Use the same Supabase project that the Qt app uses.

```powershell
Copy-Item -LiteralPath '.dev.vars.example' -Destination '.dev.vars'
npm.cmd run dev
```

This starts a loopback-only local development server. Actual generation still calls Groq and consumes provider usage; there is no mock or bypass-auth mode. Local Durable Object quota state is separate from production. Restarting `wrangler dev` normally preserves its local state.

## 3. Configure and build the Qt app

In **Qt Creator > Projects > Run Settings > Environment**, set these three values:

```text
DAILYPLANNER_API_URL=https://YOUR_WORKER.YOUR_SUBDOMAIN.workers.dev/v1/breakdown
DAILYPLANNER_SUPABASE_URL=https://PROJECT_REF.supabase.co
DAILYPLANNER_SUPABASE_PUBLISHABLE_KEY=sb_publishable_YOUR_PUBLIC_KEY
```

The API setting is the **full endpoint**, including `/v1/breakdown`. It must use HTTPS. Remove the old `GROQ_API_KEY` from the application's run environment; the app no longer reads it and has no direct-provider fallback.

For loopback development only, use:

```text
DAILYPLANNER_API_URL=http://127.0.0.1:8787/v1/breakdown
DAILYPLANNER_ALLOW_LOCAL_HTTP=1
```

The local HTTP switch only allows `localhost`, `127.0.0.1` and `::1`. Supabase still uses HTTPS. Production TLS verification stays enabled, and network redirects are not followed with credentials.

To give your friends a build that needs no environment configuration, embed only the three **public** settings through CMake cache variables of the same names. Enter them under **Qt Creator > Projects > Build Settings > CMake**. Reconfigure CMake and rebuild after changing these defaults. Run-environment values override build defaults. Do not embed Groq or Supabase admin keys.

The new sources and `AuthModal.qml` are registered in `CMakeLists.txt`; Windows links `advapi32` for Credential Manager. There is no additional Qt dependency beyond the existing Network component. Keep the existing working directory to continue using your current `planner.db`.

Windows remembers only the refresh credential in the current OS user's Credential Manager, under a `DailyPlanner/Supabase/...` entry scoped to the project URL. Access tokens remain in memory; passwords are never saved. A rotated refresh credential replaces the old one. If secure storage fails, the session lasts only until the app closes. Other platforms currently use memory-only sessions; native mobile keychain persistence can be added before mobile distribution.

Open **Menu > Sign in / Create account**. With Confirm email disabled, create an account and sign in without a code. **Forgot password?** requires working email delivery and is unavailable to friends in the current trial. Add each account's UUID to the Worker allowlist before it can use AI. Ordinary task/calendar/goal editing remains available offline and signed out.

## 4. Deployment phase — run only when you choose to publish

You deploy the local changes yourself. For your existing Worker, the Groq secret does not need to be re-entered for an ordinary code update. In PowerShell:

```powershell
Set-Location 'D:\Personal project\DailyPlanner\backend'
npm.cmd run deploy
```

Confirm the output lists `AI_ENABLED ("true")`. The Qt Run Environment endpoint is:

```text
DAILYPLANNER_API_URL=https://dailyplanner-ai.hahaj-dailyplanner.workers.dev/v1/breakdown
```

Keep `observability.enabled` as a JSON boolean (`false`), and `vars.AI_ENABLED` as a string (`"true"` or `"false"`). The deployed configuration is not updated just by saving the file.

For a **new** Worker, deploy initially with `AI_ENABLED="false"`:

```powershell
npx.cmd wrangler login
npm.cmd run deploy
npx.cmd wrangler secret put GROQ_API_KEY
```

The first deploy creates the Worker and quota namespace with AI disabled. `secret put` prompts you to enter the key privately. Cloudflare's `wrangler secret put` also creates and deploys a Worker version, so it belongs in this deployment phase, not in preparation. The Groq key must remain a Worker **secret**, never a `vars` entry, source file, command-line argument, QML field or SQLite value.

After adding the secret and approved account UUIDs, change `AI_ENABLED` to `"true"` and run:

```powershell
npm.cmd run deploy
```

Copy the deployed HTTPS URL into the Qt configuration with `/v1/breakdown` appended. Publish a rebuilt app to friends with the public settings embedded. To pause AI, set `AI_ENABLED="false"` and deploy that configuration. Local planner data remains usable.

The code has no deployment hook or CI auto-publish configuration. Cloudflare, Supabase, SMTP and Groq each have their own quotas/pricing; this app's safeguards govern AI requests, not a precise monetary bill for all four services.

References: [Worker secrets](https://developers.cloudflare.com/workers/configuration/secrets/), [Durable Object exports](https://developers.cloudflare.com/durable-objects/reference/durable-objects-migrations/), [SQLite transactions](https://developers.cloudflare.com/durable-objects/api/sqlite-storage-api/), [Groq structured outputs](https://console.groq.com/docs/structured-outputs).

## Limits and request behavior

Starter defaults in `wrangler.jsonc`:

- Each account: **3 requests per fixed UTC minute**, **30 per UTC day**, **1 in flight**.
- All accounts together: **100 per UTC day**, **1,000 per UTC month**, **2 in flight**.
- Input body: **16 KiB**, including bounded field lengths and real ISO calendar dates.
- Task output: **1–12 subtasks**, each **1–120 integer minutes**.
- Goal output: **1–8 milestone titles** and **1–12 tasks for the first milestone**, each **1–120 integer minutes**.
- Provider response body: **128 KiB** maximum; normalized Qt response: **64 KiB** maximum; completion budget: **4,096 tokens**, including the model's reasoning allowance.
- JWT key-fetch timeout: **5 seconds**. Request-body timeout: **2 seconds**. Groq request/stream timeout: **35 seconds**. Qt's overall AI timeout: **45 seconds**, including any session refresh. Auth operations have a **20-second** timeout.

Every accepted provider attempt consumes a reservation, including provider failures, malformed output and timeouts. Input/auth/quota rejections do not consume AI reservations. Counts are not refunded because an interrupted request may already have consumed Groq usage. Closing a card cancels the Qt request and discards late responses; it cannot guarantee cancellation of a request already running at the provider. Concurrency leases expire after 60 seconds if a Worker stops before releasing one.

Daily/monthly counters are checked and incremented in one synchronous storage transaction before any Groq call. All requests use the same named object across accounts and regions. Duplicate `(user UUID, request UUID)` submissions are rejected for 24 hours rather than generating twice. The app generates a fresh request UUID only for a new manual attempt. Provider retries are never automatic. Rate windows reset in UTC, independently of the calendar's local dates. The overall cap is a hard **request-count** cap, combined with bounded input and completion size, rather than an exact token-spend or currency cap. Fixed minute windows can allow a burst at a minute boundary.

The server controls the model, prompt versions and JSON schema. Client-supplied model names, provider URLs, custom instructions, user IDs and unknown fields are rejected. The original task estimate stays a soft guideline: honest AI estimates can exceed it, and the existing preview shows the difference.

## API contract

`GET /health` returns service liveness only; it does not verify secrets, account setup, Groq availability or quota state.

`POST /v1/breakdown` requires `Content-Type: application/json` and `Authorization: Bearer <Supabase access token>`.

Example task body:

```json
{
  "kind": "task",
  "requestId": "fcb2a1f0-1034-4a7b-94b8-3f4601e66319",
  "context": {
    "title": "Prepare a presentation",
    "description": "A ten-minute talk about renewable energy",
    "category": "Work",
    "estimatedMinutes": 120
  }
}
```

Example goal body:

```json
{
  "kind": "goal",
  "requestId": "92ceca95-31c6-4a8e-8b3b-70a6caeb4112",
  "context": {
    "title": "Build a small portfolio website",
    "description": "Show three completed projects",
    "category": "Personal",
    "successCriteria": "Publish a working site with three project pages",
    "startingPoint": "I know basic HTML",
    "targetDate": "2026-12-01",
    "weeklyHours": 4,
    "today": "2026-10-02"
  }
}
```

All shown context fields are required; optional text can be an empty string, including `targetDate`. `weeklyHours=0` means unspecified availability. Task estimates accept integers from 1 to 10,080 minutes. Title/category bounds are 200/80 characters, description 4,000, success criteria and starting point 2,000 each. The entire UTF-8 request still must fit 16 KiB.

Task success is `{ "kind": "task", "requestId": "...", "subtasks": [{ "name": "...", "description": "...", "minutes": 20 }] }`. Goal success replaces `subtasks` with `milestones: ["..."]` and `tasks: [...]`. Qt checks request UUID and task/goal kind, retains the selected local database ID, validates the steps again, and emits the existing preview signals. Database IDs are not sent to the server.

Errors have a safe shape:

```json
{
  "error": {
    "code": "USER_USAGE_LIMIT",
    "message": "Your AI usage allowance for this period is used up. Try again after it resets.",
    "retryAfterSeconds": 60
  },
  "requestId": "..."
}
```

HTTP errors include 400 invalid input, 401 missing/expired session, 403 account not enabled, 409 duplicate submission, 413 body too large, 415 wrong content type, 429 quota/concurrency/provider limit, 502 invalid/provider failure, 503 configuration/unavailability, and 504 timeout. A 429 includes `Retry-After`. Raw provider errors and credentials are not returned. No permissive browser CORS is enabled; this endpoint is intended for the native Qt client.

## Breakdown error handling

The Groq call uses `redirect: "manual"`. Cloudflare's runtime rejects `redirect: "error"` before sending a request, which previously appeared as a connection failure. Any redirect response is rejected explicitly; credentials are never forwarded to a redirect target.

The server reports separate errors for disabled AI, a missing Groq secret, malformed key syntax, Groq 401 authentication failures, 403 access restrictions, unavailable models, rejected schemas/request settings, provider rate limits, timeouts, connection failures, invalid responses, refusals, and response-token limits. Locally detected missing/malformed keys do not consume an AI reservation. Provider attempts still count on failure.

Groq rejections include the upstream HTTP status in `error.message`, which the existing Qt AIService already displays. `error.provider` also contains `status` and, where recognized, `code` and `parameter`. Only fixed allowlisted identifiers are returned. Raw provider messages, generated error text, task context, authorization headers, exception text, and credentials are never echoed or logged. Unexpected provider identifiers are omitted. Error bodies are bounded to 16 KiB and a 5-second read deadline within the overall 35-second provider timeout. Slow error-body parsing falls back to the known HTTP status.

For example, a schema rejection may return:

```json
{
  "error": {
    "code": "PROVIDER_SCHEMA_REJECTED",
    "message": "Groq rejected the breakdown schema or structured-output settings. The server request needs attention (Groq HTTP 400; code: invalid_request_error; parameter: response_format).",
    "provider": { "status": 400, "code": "invalid_request_error", "parameter": "response_format" }
  },
  "requestId": "..."
}
```

Copy the visible error message when reporting a failed request. Do not share the Groq key. A provider HTTP 400/422 is a rejected request, not evidence of a bad key; HTTP 401 indicates provider authentication failure. The previous generic error did not expose enough information to identify the current live rejection. Its exact cause still needs the new diagnostic from your deployed version; no live reproduction was performed by Codex.

## Manual verification left to you

No tests, builds, typechecks, dry-run bundles, deployment, or live Groq requests were run by Codex during this review. Manual verification and deployment are yours. Existing direct-Groq tests in `tests/test_dailyplanner.cpp` predate this contract and need migration before they can validate the authenticated backend flow. No live Groq smoke test is automatic in the app. Keep the existing quota namespace when deploying so counters are preserved.
