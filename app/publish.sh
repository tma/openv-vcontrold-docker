#!/bin/bash
set -euo pipefail

SUBTOPIC="${1:-}"
FULL_TOPIC="$MQTTTOPIC/$SUBTOPIC"
PAYLOAD=$(cat)

mosquitto_pub \
  -u "$MQTTUSER" -P "$MQTTPASSWORD" \
  -h "$MQTTHOST" -p "$MQTTPORT" \
  -t "$FULL_TOPIC" \
  -m "$PAYLOAD" \
  -x 120 -c --id "VCONTROLD-PUB" -V "mqttv5"
