#!/bin/bash
set -euo pipefail

. /app/common.sh
mqtt_require_env
mapfile -t MOSQUITTO_ARGS < <(mosquitto_arguments "$MQTT_HOST" "$MQTT_PORT" "$MQTT_USER" "$MQTT_PASSWORD")

# Use a while loop that restarts the subscription if it crashes
while true; do
    echo "Starting MQTT subscription..."

    mosquitto_sub \
        "${MOSQUITTO_ARGS[@]}" \
        -t "${MQTT_TOPIC}/request" \
    | while read -r payload; do
        if [ -z "$payload" ]; then
            continue
        fi

        # Capture output, don't crash on error
        if response=$(vclient -h 127.0.0.1:3002 -c "${payload}" -j 2>/dev/null); then
            mosquitto_pub \
                "${MOSQUITTO_ARGS[@]}" \
                -t "${MQTT_TOPIC}/response" \
                -m "$response" \
                -V "mqttv5" \
                -W 10
        else
            echo "Error executing command: $payload"
        fi
    done

    echo "MQTT subscriber disconnected. Retrying in 10s..."
    sleep 10
done
