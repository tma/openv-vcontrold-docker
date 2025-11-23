#!/bin/bash
set -euo pipefail

. /app/common.sh
mqtt_require_env
mapfile -t MOSQUITTO_ARGS < <(mosquitto_arguments "$MQTT_HOST" "$MQTT_PORT" "$MQTT_USER" "$MQTT_PASSWORD")

SUBTOPIC="${1:-}"
FULL_TOPIC="${MQTT_TOPIC}/${SUBTOPIC}"
PAYLOAD=$(cat)

# Publish message
mosquitto_pub \
  "${MOSQUITTO_ARGS[@]}" \
  -t "$FULL_TOPIC" \
  -m "$PAYLOAD" \
  -V "mqttv5" \
  -W 10
