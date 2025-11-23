#!/bin/bash
set -euo pipefail

# Validate environment
if [[ -z "${MQTTHOST:-}" ]] || [[ -z "${MQTTTOPIC:-}" ]]; then
    echo "Error: MQTTHOST or MQTTTOPIC is not set" >&2
    exit 1
fi

SUBTOPIC="${1:-}"
FULL_TOPIC="${MQTTTOPIC}/${SUBTOPIC}"
PAYLOAD=$(cat)

# Publish message
mosquitto_pub \
  -u "${MQTTUSER:-}" -P "${MQTTPASSWORD:-}" \
  -h "${MQTTHOST}" -p "${MQTTPORT:-1883}" \
  -t "$FULL_TOPIC" \
  -m "$PAYLOAD" \
  -V "mqttv5" \
  -W 10
