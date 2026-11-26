# Diagnostics Relay (Cloudflare Workers + D1)

The Android app records diagnostic reports to its private local queue first. A report leaves the device only after explicit consent and either an explicit per-report approval or the separately enabled automatic-reporting setting. Review-before-upload is enabled by default. Relay credentials are stored with Android secure storage and never included in local export or report JSON.

This repository includes a minimal Cloudflare Worker relay at `apps/relay/cloudflare-worker/`. The Worker accepts only the app's v2 payload and stores an allowlisted report in D1. It does **not** create GitHub Issues. The repository name in the request is metadata only.

## Deploy the relay

Prerequisites: a Cloudflare account with Workers and D1 enabled, Node.js/npm, and Wrangler (`npm install --global wrangler`). Run the following commands from `apps/relay/cloudflare-worker`:

1. Authenticate with Wrangler: `wrangler login`.
2. Create the database: `wrangler d1 create cybersecurity-assistant-diagnostics`.
3. Copy the generated database ID into `wrangler.toml` in place of `REPLACE_WITH_CREATED_D1_DATABASE_ID`.
4. Initialize its schema: `wrangler d1 execute cybersecurity-assistant-diagnostics --remote --file=./schema.sql`.
5. Generate a high-entropy bearer token (at least 32 characters) and set it as a Worker secret: `wrangler secret put RELAY_BEARER_TOKEN`.
6. Deploy: `wrangler deploy`.

The deployed endpoint is `https://<worker-name>.<account-subdomain>.workers.dev/diagnostics`. Confirm that `GET` returns a small health response before configuring the app. `POST` requires the exact bearer token and accepts JSON schema version 2 only. Keep D1 access and Cloudflare account access restricted. Rotate the relay token by updating the Worker secret and replacing the saved token in the app; do not place it in source control, URL query parameters, screenshots, or support tickets.

## Configure the Android app

Open **Diagnostics Developer** in the app. Set the relay's HTTPS URL, leave review-before-upload enabled unless you explicitly want unattended upload, and paste the bearer token in the dedicated secure-token field. Select explicit upload consent, save settings, and use **Test relay**. The test sends a GET health check; it does not upload a report. Review an individual report and choose upload to authorize that report. Automatic upload requires all three: explicit consent, automatic reporting enabled, and review-before-upload disabled.

A network failure does not block app use. Approved reports remain in the local queue and retry with bounded backoff. Clearing the relay token or changing the endpoint revokes queued approvals. The app does not send IMEI, Android ID, device serial, account identity, or other unique device identifiers by default. Error text and stack traces are sanitized on-device; the Worker also rejects oversized or malformed fields and ignores unknown request fields.

## Privacy, retention, and operations

D1 stores report content and a relay receive timestamp. Configure a retention/deletion process appropriate to your deployment and disclose the relay operator to users. Back up and delete D1 data under your own retention policy. Do not enable public read access. The shared bearer token is a transport gate, not a per-user identity or a substitute for Cloudflare account security; anyone who obtains it can submit reports. Consider adding per-user relay credentials and stricter rate limits for a public deployment.

The app's optional GitHub repository field does not create Issues. A future GitHub Issues integration must run server-side, keep GitHub credentials only in Worker secrets, create Issues only after separate explicit opt-in, and send sanitized summaries only. Never embed a GitHub token in the APK.

## Local verification

`GET /diagnostics` returns health status. A valid authenticated `POST` with a schema v2 report returns `202`; unauthenticated requests return `401`; invalid JSON/report payloads return `400`; other paths return `404`. The Worker does not return stored report contents. Deploy with `wrangler deploy` after making changes.
