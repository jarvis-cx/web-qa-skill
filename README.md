# web-qa — OpenClaw Skill for Automated Web QA

Automated web QA monitoring that runs on an OpenClaw cron schedule. Checks your web app across three tiers of increasing depth:

| Tier | Name | Frequency | What it checks |
|------|------|-----------|----------------|
| 0 | Smoke | Every 30 min | HTTP status, HTTPS redirect, response time, health endpoint |
| 1 | Functional | Every 2 hours | Known job status, security headers, API responses, email/domain verification |
| 2 | Deep E2E | Every 6 hours | Submits a real test job, polls until complete, verifies report URL, cleans up |

Failures alert instantly via Telegram. A daily digest is sent at 09:00.

## How It Works

1. **OpenClaw cron** triggers the skill every 30 minutes
2. The agent reads `SKILL.md` and loads the project config (e.g. `configs/triptrust.json`)
3. A **state file** tracks when each tier last ran, preventing redundant checks
4. Each tier runs only if enough time has elapsed since its last execution
5. On failure → immediate Telegram alert with details
6. At digest time → summary of all checks from the last 24 hours

### Tier Details

**Tier 0 — Smoke:**
- `GET /` returns 200, response body is non-empty
- HTTPS redirect works (http → https)
- Response time under configured threshold (default 3s)
- Health/status endpoint responds

**Tier 1 — Functional:**
- Known completed job is still accessible via API
- Security headers present (`X-Frame-Options`, `Strict-Transport-Security`, etc.)
- API endpoints return expected shapes
- Email domain (Resend) DNS verification status
- Supabase connectivity

**Tier 2 — Deep E2E:**
- Submits a real test job using configured test data
- Polls job status until completion (timeout configurable, default 20 min)
- Verifies the generated report URL is accessible
- Cleans up test data after configured retention period

## Setup

1. **Install [OpenClaw](https://openclaw.ai)**

2. **Copy skill files:**
   ```bash
   cp -r web-qa ~/.openclaw/skills/web-qa/
   ```

3. **Create a config** in `configs/` for your project (see `configs/triptrust.json` as a reference)

4. **Add secrets** to macOS Keychain as referenced in your config:
   ```bash
   security add-generic-password -a openclaw -s SUPABASE_URL -w "your-url"
   security add-generic-password -a openclaw -s SUPABASE_SERVICE_ROLE_KEY -w "your-key"
   ```

5. **Register the cron:**
   ```bash
   openclaw cron create \
     --name "web-qa-myproject" \
     --schedule "every 30m" \
     --message "Read ~/.openclaw/skills/web-qa/SKILL.md and run QA checks for myproject"
   ```

## Config Format

Project configs live in `configs/` as JSON files. Here's the full schema based on `triptrust.json`:

```jsonc
{
  // Project identifier and display name
  "project": "myproject",
  "name": "My Project",

  // Base URL of the web app to test
  "baseUrl": "https://www.example.com",

  // Alert delivery
  "alertChannel": "telegram",
  "alertTarget": "CHAT_ID",
  "digestTime": "09:00",
  "timezone": "Asia/Hong_Kong",

  // Where to persist check state (last-run timestamps, results)
  "stateFile": "~/.openclaw/workspace/memory/web-qa-state.json",

  // Secrets pulled from macOS Keychain
  "secrets": {
    "supabaseUrl": { "keychain": "SUPABASE_URL" },
    "supabaseServiceKey": { "keychain": "SUPABASE_SERVICE_ROLE_KEY" },
    "resendKey": { "keychain": "RESEND_API_KEY" }
  },

  // Test data for E2E tier
  "testData": {
    "email": "test+qa@example.com",
    "isTestFlag": true,
    "passports": ["Australian"],
    "tripPurpose": "holiday",
    "budgetLevel": "moderate",
    "concerns": "QA automated test — please ignore",
    "destinationsFile": "~/.openclaw/skills/web-qa/data/destinations.json",
    "cleanupAfterHours": 24
  },

  // Known jobs for functional checks (verify they remain accessible)
  "knownJobs": {
    "done": "JOB_ID"
  },

  // Resend domain ID for email verification checks
  "resendDomainId": "DOMAIN_UUID",

  // Check intervals
  "checks": {
    "smoke": { "intervalMinutes": 30 },
    "functional": { "intervalMinutes": 120 },
    "e2e": { "intervalMinutes": 360, "timeoutMinutes": 20 },
    "daily": { "cronHKT": "02:00" }
  },

  // Performance thresholds
  "thresholds": {
    "responseTimeMs": 3000,
    "e2eTimeoutMinutes": 20
  }
}
```

## Directory Structure

```
web-qa/
  SKILL.md            # Main skill instructions for the OpenClaw agent
  README.md           # This file
  .gitignore
  configs/            # Per-project config files
    triptrust.json    # Example config for TripTrust
  data/               # Test data (e.g. destinations list for E2E)
  scripts/            # Helper scripts
```

## Requirements

- **[OpenClaw](https://openclaw.ai)** — agent runtime and cron scheduler
- **Telegram bot** configured in OpenClaw — for failure alerts and daily digests
- **macOS Keychain** — secrets for any credentials referenced in your project config
