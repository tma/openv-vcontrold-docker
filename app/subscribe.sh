#!/bin/bash
set -euo pipefail

. /app/common.sh
mqtt_require_env
SUB_CLIENT_ID="${MQTT_CLIENT_ID_PREFIX}-sub-$(hostname)"
mapfile -t MOSQUITTO_SUB_ARGS < <(mosquitto_arguments "$MQTT_HOST" "$MQTT_PORT" "$MQTT_USER" "$MQTT_PASSWORD" "$SUB_CLIENT_ID")

# Use a while loop that restarts the subscription if it crashes
while true; do
    echo "Starting MQTT subscription..."

    mosquitto_sub \
        "${MOSQUITTO_SUB_ARGS[@]}" \
        -t "${MQTT_TOPIC}/request" \
    | while read -r payload; do
        if [ -z "$payload" ]; then
            continue
        fi

        if [ "${DEBUG:-false}" = true ]; then
            echo "Debug: Received MQTT request: $payload"
        fi

        # Capture both stdout and stderr, always publish the response
        response=$(vclient -h 127.0.0.1:3002 -c "${payload}" -j 2>&1)

        if [ -n "$response" ]; then
            /app/publish.sh "response" <<< "$response"
        else
            echo "Error: No response for command: $payload"
        fi
    done

    echo "MQTT subscriber disconnected. Retrying in 10s..."
    sleep 10
done
