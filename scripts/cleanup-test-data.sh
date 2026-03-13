#!/bin/bash
SUPABASE_URL=$(security find-generic-password -a openclaw -s SUPABASE_URL -w 2>/dev/null)
SERVICE_KEY=$(security find-generic-password -a openclaw -s SUPABASE_SERVICE_ROLE_KEY -w 2>/dev/null)

# Delete test jobs older than 24 hours
CUTOFF=$(python3 -c "from datetime import datetime, timedelta, timezone; print((datetime.now(timezone.utc) - timedelta(hours=24)).strftime('%Y-%m-%dT%H:%M:%SZ'))")

RESULT=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
  "$SUPABASE_URL/rest/v1/jobs?is_test=eq.true&created_at=lt.$CUTOFF" \
  -H "apikey: $SERVICE_KEY" \
  -H "Authorization: Bearer $SERVICE_KEY")

echo "Cleanup result: $RESULT"
