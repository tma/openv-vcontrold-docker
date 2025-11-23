#!/bin/bash
set -euo pipefail

# Basic env validation
if [[ -z "${MQTTHOST:-}" ]] || [[ -z "${MQTTTOPIC:-}" ]]; then
    echo "Error: MQTTHOST or MQTTTOPIC is not set" >&2
    exit 1
fi

# Use a while loop that restarts the subscription if it crashes
while true; do
    echo "Starting MQTT subscription..."

    mosquitto_sub \
        -u "${MQTTUSER:-}" -P "${MQTTPASSWORD:-}" \
        -h "${MQTTHOST}" -p "${MQTTPORT:-1883}" \
        -t "${MQTTTOPIC}/request" \
    | while read -r payload; do
        if [ -z "$payload" ]; then
            continue
        fi

        # Capture output, don't crash on error
        if response=$(vclient -h 127.0.0.1:3002 -c "${payload}" -j 2>/dev/null); then
            mosquitto_pub \
                -u "${MQTTUSER:-}" -P "${MQTTPASSWORD:-}" \
                -h "${MQTTHOST}" -p "${MQTTPORT:-1883}" \
                -t "${MQTTTOPIC}/response" \
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
