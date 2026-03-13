# web-qa — Automated QA Monitoring Skill

**Trigger:** Cron message referencing this SKILL.md
**Description:** Runs tiered synthetic monitoring checks against web applications and alerts on failures via Telegram.

---

## How to Use

You are invoked by cron every 30 minutes with a config path. Follow these steps **exactly** in order.

## Step 0: Load Config & Secrets

1. Read the config JSON file specified in the cron message (e.g. `~/.openclaw/skills/web-qa/configs/triptrust.json`)
2. Extract all values: `baseUrl`, `alertTarget`, `knownJobs`, `resendDomainId`, `testData`, `thresholds`, `checks`
3. Load secrets from macOS Keychain:
   ```bash
   security find-generic-password -a openclaw -s SUPABASE_URL -w
   security find-generic-password -a openclaw -s SUPABASE_SERVICE_ROLE_KEY -w
   security find-generic-password -a openclaw -s RESEND_API_KEY -w
   ```
4. Read state file at `~/.openclaw/workspace/memory/web-qa-state.json`. If it doesn't exist, create it with empty defaults.

## Step 1: Determine Which Tiers to Run

Compare current time against state file timestamps:

| Tier | Run if elapsed since last run |
|------|-------------------------------|
| Smoke (Tier 0) | Always run every invocation |
| Functional (Tier 1) | ≥ 2 hours since `lastFunctionalRun` |
| Deep E2E (Tier 2) | ≥ 6 hours since `lastE2eRun` |
| Daily Digest | Current time is between 09:00–09:30 HKT AND `lastDigestSent` was not today |

## Step 2: Run Smoke Checks (Tier 0)

Run ALL of these using `exec` with `curl`. Do NOT use the browser tool.

| # | Check Name | Command | Pass Criteria |
|---|-----------|---------|---------------|
| S1 | homepage | `curl -s -o /dev/null -w "%{http_code}" --max-time 10 {baseUrl}` | HTTP 200 |
| S2 | homepage-body | `curl -s --max-time 10 {baseUrl}` | Body contains "TripTrust" |
| S3 | https-redirect | `curl -s -o /dev/null -w "%{http_code}" --max-time 10 -L http://triptrust.co` | Final URL starts with `https://` |
| S4 | response-time | `curl -s -o /dev/null -w "%{time_total}" --max-time 10 {baseUrl}` | time_total < 3.0 seconds |
| S5 | get-report-page | `curl -s -o /dev/null -w "%{http_code}" --max-time 10 {baseUrl}/get-report` | HTTP 200 |
| S6 | health-endpoint | `curl -s --max-time 10 {baseUrl}/api/health` | HTTP 200 AND body contains `"status":"ok"` |
| S7 | reports-api | `curl -s --max-time 10 {baseUrl}/api/reports` | HTTP 200 AND body starts with `[` (JSON array) |

**Severity:** P0 🔴 — alert immediately on failure, no quiet hours.

## Step 3: Run Functional Checks (Tier 1) — if 2h elapsed

| # | Check Name | Command | Pass Criteria |
|---|-----------|---------|---------------|
| F1 | known-job-status | `curl -s {baseUrl}/api/jobs/{knownJobs.done}` | Body contains `"status":"done"` AND contains `reportUrl` |
| F2 | no-email-leak | `curl -s {baseUrl}/api/reports` | Body does NOT contain `@` character |
| F3 | places-api | `curl -s -o /dev/null -w "%{http_code}" --max-time 10 "{baseUrl}/api/places?q=Tokyo"` | HTTP 200 |
| F4 | security-headers | `curl -sI {baseUrl}` | Response contains ALL of: `x-frame-options`, `x-content-type-options`, `strict-transport-security` (case-insensitive) |
| F5 | webhook-auth | `curl -s -o /dev/null -w "%{http_code}" -X PATCH {baseUrl}/api/webhook/status-update` | HTTP 401 or 403 |
| F6 | resend-domain | `curl -s -H "Authorization: Bearer {RESEND_API_KEY}" https://api.resend.com/domains/{resendDomainId}` | Body contains `"verified"` |
| F7 | supabase-count | `curl -s -H "apikey: {SERVICE_KEY}" -H "Authorization: Bearer {SERVICE_KEY}" "{SUPABASE_URL}/rest/v1/jobs?select=count" ` | Returns valid JSON with a count |
| F8 | stripe-checkout | `curl -s -X POST {baseUrl}/api/stripe/checkout -H "Content-Type: application/json" -d '{"shortId":"{knownJobs.unpaid}"}'` | HTTP 200 AND body contains `"url"` AND body contains `"stripe.com"` |

**Severity:** P1 🟠 — alert during 08:00–23:00 HKT only. Outside quiet hours, queue for digest.

## Step 4: Run Deep E2E (Tier 2) — if 6h elapsed

1. **Pick destination:**
   ```bash
   bash ~/.openclaw/skills/web-qa/scripts/pick-destination.sh
   ```
   Capture the output as DESTINATION.

2. **Calculate travel dates:** Use dates 30–60 days from now (start = +30d, end = +37d).

3. **Submit test job:**
   ```bash
   curl -s -X POST {baseUrl}/api/jobs \
     -H "Content-Type: application/json" \
     -d '{
       "destinations": ["DESTINATION"],
       "travelDateStart": "YYYY-MM-DD",
       "travelDateEnd": "YYYY-MM-DD",
       "passports": ["Australian"],
       "adults": 1,
       "children": [],
       "tripPurpose": "holiday",
       "budgetLevel": "moderate",
       "concerns": "QA automated test — please ignore",
       "email": "jarvis+qa@chapman.cx",
       "isTest": true
     }'
   ```
   Capture `jobId` from response.

4. **Poll for completion:** Every 60 seconds, up to 20 minutes:
   ```bash
   curl -s {baseUrl}/api/jobs/{jobId}
   ```
   Wait until `status` is `"done"` and `reportUrl` is present.

5. **Verify report:** `GET {reportUrl}` — must return HTTP 200 and body must contain the destination name.

6. **Test Stripe checkout + payment flow (using promo code ALPHA = 100% off):**
   - POST `{baseUrl}/api/stripe/checkout` with `{"shortId": "{jobId}"}` — verify HTTP 200 and response contains `"url"` and `"stripe.com"`
   - Open the Stripe checkout URL using the browser tool
   - Enter test card: `4242 4242 4242 4242`, expiry `12/29`, CVC `123`, any ZIP
   - Apply promo code: `ALPHA`
   - Complete checkout — verify it succeeds (Stripe redirects back to `{baseUrl}/r/{jobId}`)
   - Verify `GET {baseUrl}/api/jobs/{jobId}` returns `"is_paid": true`
   - Verify `GET {baseUrl}/r/{jobId}` now serves the full (unblurred) report

7. **Cleanup:** Run `bash ~/.openclaw/skills/web-qa/scripts/cleanup-test-data.sh`

7. Record: destination, jobId, duration, pass/fail.

**Severity:** P1 🟠 — alert with destination, jobId, failure step, and duration.

## Step 5: Alert Logic

### On any check failure:
1. Wait 30 seconds
2. Re-run the exact same failing check
3. If it passes on retry: record as "flaky" in state, do NOT alert
4. If still failing: proceed to alert

### Before alerting, check dedup:
- Read `lastAlerts` from state file
- If the same check name was alerted within the last 1 hour: do NOT re-alert
- Exception: P0 always alerts regardless of dedup

### Send alert via `message` tool:
- action: `send`
- target: `{alertTarget}` from config
- Format:
```
🚨 {name} QA Alert — {SEVERITY}

❌ FAILED: {check_name}
📍 What: {description}
💥 Error: {error_message}
🕐 Time: {HKT timestamp}
🔁 Retried: Yes (30s delay) — still failing

👉 Check: {relevant_url}
```

### Quiet hours (P1 only):
- Between 23:00–08:00 HKT: do NOT send P1 alerts
- Record them in state file under `queuedAlerts` for the morning digest
- P0 alerts ALWAYS fire regardless of time

### Auto-resolve:
- If a check that was previously failing now passes, send:
```
✅ {name} QA — Resolved

✅ {check_name} is passing again
🕐 Time: {HKT timestamp}
⏱️ Was failing for: {duration}
```

## Step 6: Daily Digest

If current HKT time is between 09:00 and 09:30, AND `lastDigestSent` in state was not today:

Send via `message` tool to `{alertTarget}`:
```
✅ {name} QA — Daily Report
📅 {day_of_week} {date}

Smoke checks: {pass}/{total} passed (last 24h)
Functional checks: {pass}/{total} passed
Deep E2E runs: {pass}/{total} passed (avg {duration})

Last E2E: {destination} {✅/❌} ({duration})
Next E2E: ~{time} HKT

{If any queued alerts from quiet hours, list them here}
```

Update `lastDigestSent` in state file to today's date.

## Step 7: Update State File

⚠️ **CRITICAL: Always write the state file at the END of every run, even if checks were skipped.** Failure to write results in repeated E2E job submissions on every cron cycle.

Update timestamps for every tier that ran. If a tier was skipped (interval not elapsed), keep its existing timestamp unchanged.

After all checks complete, write updated state to `~/.openclaw/workspace/memory/web-qa-state.json`:

```json
{
  "lastSmokeRun": "ISO timestamp",
  "lastFunctionalRun": "ISO timestamp",
  "lastE2eRun": "ISO timestamp",
  "lastDigestSent": "YYYY-MM-DD",
  "lastE2eDestination": "city name",
  "lastE2eDuration": "seconds",
  "lastE2eJobId": "shortId",
  "lastAlerts": {
    "check_name": "ISO timestamp of last alert"
  },
  "queuedAlerts": [],
  "failingChecks": ["check_name"],
  "smokeResults": { "pass": 7, "total": 7 },
  "functionalResults": { "pass": 8, "total": 8 },
  "e2eResults": { "pass": 1, "total": 1 }
}
```

## Step 8: Final Response

- If everything passed and no digest was sent: respond with **HEARTBEAT_OK**
- If alerts were sent: respond with a summary of what failed
- If digest was sent: respond with "Daily digest sent"

---

## Important Rules

1. **Use `exec` with `curl` for all HTTP checks.** Do NOT use the browser tool.
2. **Always read the config file first** — never hardcode URLs or secrets.
3. **Always load secrets from Keychain** — never log or expose them.
4. **Always check state file for dedup** before alerting.
5. **Always retry once** before alerting on failure.
6. **Never skip cleanup** after E2E runs.
7. **Respect quiet hours** for P1 alerts (23:00–08:00 HKT).
8. **P0 alerts have no quiet hours** — always fire immediately.
9. **Keep responses minimal** — HEARTBEAT_OK when all clear.
