#!/bin/bash
# Pick a random destination from destinations.json using timestamp as seed
DEST_FILE="$HOME/.openclaw/skills/web-qa/data/destinations.json"
COUNT=$(python3 -c "import json; print(len(json.load(open('$DEST_FILE'))))")
IDX=$(($(date +%s) % COUNT))
python3 -c "import json; dests=json.load(open('$DEST_FILE')); print(dests[$IDX])"
