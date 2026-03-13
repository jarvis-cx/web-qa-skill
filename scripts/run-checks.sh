#!/bin/bash
# Usage: ./run-checks.sh <check_name> <url> [expected_status] [expected_body_contains]
CHECK=$1
URL=$2
EXPECTED_STATUS=${3:-200}
EXPECTED_BODY=${4:-""}

START=$(python3 -c "import time; print(int(time.time()*1000))")
RESPONSE=$(curl -s -L -o /tmp/qa_body.txt -w "%{http_code}" --max-time 10 "$URL")
END=$(python3 -c "import time; print(int(time.time()*1000))")
DURATION=$((END - START))
BODY=$(cat /tmp/qa_body.txt)

if [ "$RESPONSE" != "$EXPECTED_STATUS" ]; then
  echo "{\"check\":\"$CHECK\",\"pass\":false,\"error\":\"Expected HTTP $EXPECTED_STATUS, got $RESPONSE\",\"duration\":$DURATION}"
  exit 1
fi

if [ -n "$EXPECTED_BODY" ] && ! echo "$BODY" | grep -q "$EXPECTED_BODY"; then
  echo "{\"check\":\"$CHECK\",\"pass\":false,\"error\":\"Body missing: $EXPECTED_BODY\",\"duration\":$DURATION}"
  exit 1
fi

echo "{\"check\":\"$CHECK\",\"pass\":true,\"duration\":$DURATION}"
exit 0
