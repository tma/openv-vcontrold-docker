#!/bin/bash
set -euo pipefail

# Configuration with defaults
USB_DEVICE="${USB_DEVICE:-/dev/vitocal}"
MAX_LENGTH="${MAX_LENGTH:-512}"
VCONTROLD_HOST="127.0.0.1"
VCONTROLD_PORT="3002"
PID_FILE="/tmp/vcontrold.pid"
MQTT_ACTIVE="${MQTT_ACTIVE:-false}"
MQTT_SUBSCRIBE="${MQTT_SUBSCRIBE:-false}"

echo "Device: ${USB_DEVICE}"

# Cleanup handler
cleanup() {
    echo "Received shutdown signal. Exiting..."
    if [ -f "$PID_FILE" ]; then
        kill "$(cat "$PID_FILE")" 2>/dev/null || true
    fi
    exit 0
}
trap cleanup SIGTERM SIGINT

### Execution

# Remove stale pid file
rm -f "$PID_FILE"

# Start vcontrold
echo "Starting vcontrold..."
vcontrold -x /config/vcontrold.xml -P "$PID_FILE"

# Wait for vcontrold to be ready (checking port availability)
echo "Waiting for vcontrold to accept connections..."
MAX_RETRIES=30
count=0
while ! vclient -h "$VCONTROLD_HOST:$VCONTROLD_PORT" -c "version" >/dev/null 2>&1; do
    sleep 1
    count=$((count+1))
    if [ "$count" -ge "$MAX_RETRIES" ]; then
        echo "Error: vcontrold failed to start within $MAX_RETRIES seconds."
        exit 1
    fi
done

PID=$(cat "$PID_FILE")
echo "vcontrold started (PID $PID)"

if [ "${MQTT_ACTIVE}" = true ]; then
    echo "MQTT: active"
    echo "Update interval: ${INTERVAL:-60} sec"

    # Start subscriber in background if enabled (default: false)
    if [ "${MQTT_SUBSCRIBE}" = true ]; then
        if [ -f "/app/subscribe.sh" ]; then
            echo "MQTT: Starting subscriber..."
            /app/subscribe.sh &
            SUB_PID=$!
        else
            echo "Warning: /app/subscribe.sh not found, skipping subscription."
        fi
    else
        echo "MQTT: Subscription disabled via MQTT_SUBSCRIBE env var."
    fi

    execute_vclient_and_publish_values() {
        local current_list=$1
        local response

        # Run vclient with error checking
        if ! response=$(vclient -h "$VCONTROLD_HOST:$VCONTROLD_PORT" -c "${current_list}" -j 2>/dev/null); then
            echo "Warning: vclient command failed for list: $current_list"
            return
        fi

        # Parse and publish
        echo "$response" | jq -r 'to_entries[] | "\(.key) \(.value.value)"' | while read -r cmd value; do
            MQTT_SUBTOPIC="info/${cmd}"
            /app/publish.sh "$MQTT_SUBTOPIC" <<< "$value"
        done
    }

    while true; do
        # Check if vcontrold is still running
        if ! kill -0 "$PID" 2>/dev/null; then
            echo "Error: vcontrold process died. Exiting."
            exit 1
        fi

        # Skip if no commands configured
        if [ -z "${COMMANDS:-}" ]; then
            sleep "${INTERVAL:-60}"
            continue
        fi

        sublist=""
        old_ifs=$IFS
        IFS=','
        for cmd in $COMMANDS; do
            if [[ ${#sublist} -eq 0 ]]; then
                sublist="$cmd"
            elif (( ${#sublist} + ${#cmd} + 1 <= MAX_LENGTH )); then
                sublist+=",$cmd"
            else
                execute_vclient_and_publish_values "$sublist"
                sublist="$cmd"
            fi
        done
        IFS=$old_ifs

        if [[ -n $sublist ]]; then
            execute_vclient_and_publish_values "$sublist"
        fi

        sleep "${INTERVAL:-60}"
    done
else
    echo "MQTT: inactive"
    # Simple keepalive loop
    while true; do
        if ! kill -0 "$PID" 2>/dev/null; then
            echo "Error: vcontrold process died. Exiting."
            exit 1
        fi
        sleep 60
    done
fi
