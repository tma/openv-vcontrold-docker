#!/bin/bash
set -euo pipefail

. /app/common.sh
mqtt_require_env
PUB_CLIENT_ID="${MQTT_CLIENT_ID_PREFIX}-pub-$(hostname)-$$-$(date +%s)"
mapfile -t MOSQUITTO_ARGS < <(mosquitto_arguments "$MQTT_HOST" "$MQTT_PORT" "$MQTT_USER" "$MQTT_PASSWORD" "$PUB_CLIENT_ID")

SUBTOPIC="${1:-}"
FULL_TOPIC="${MQTT_TOPIC}/${SUBTOPIC}"
PAYLOAD=$(cat)

if [ "${DEBUG:-false}" = true ]; then
    echo "Debug: Publishing to $FULL_TOPIC: $PAYLOAD"
fi

MOSQUITTO_TIMEOUT="${MQTT_TIMEOUT:-10}"
MOSQUITTO_BIN=(mosquitto_pub "${MOSQUITTO_ARGS[@]}" -t "$FULL_TOPIC" -m "$PAYLOAD" -V "mqttv5")

if command -v timeout >/dev/null 2>&1; then
  timeout --foreground "${MOSQUITTO_TIMEOUT}s" "${MOSQUITTO_BIN[@]}"
else
  "${MOSQUITTO_BIN[@]}"
fi
