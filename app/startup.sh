#!/bin/bash
set -euo pipefail

# Configuration with defaults
USB_DEVICE="${USB_DEVICE:-/dev/vitocal}"
MAX_LENGTH="${MAX_LENGTH:-512}"
VCONTROLD_HOST="127.0.0.1"
VCONTROLD_PORT="3002"
PID_FILE="/tmp/vcontrold.pid"
SLEEP_PID=""
SUB_PID=""
MQTT_ACTIVE="${MQTT_ACTIVE:-false}"
MQTT_SUBSCRIBE="${MQTT_SUBSCRIBE:-false}"
export DEBUG="${DEBUG:-false}"

# Cleanup handler
cleanup() {
    echo "Received shutdown signal. Exiting..."
    if [ -f "$PID_FILE" ]; then
        kill "$(cat "$PID_FILE")" 2>/dev/null || true
    fi
    if [[ -n "$SLEEP_PID" ]]; then
        kill "$SLEEP_PID" 2>/dev/null || true
    fi
    if [[ -n "$SUB_PID" ]]; then
        kill "$SUB_PID" 2>/dev/null || true
        wait "$SUB_PID" 2>/dev/null || true
    fi
    exit 0
}
trap cleanup SIGTERM SIGINT

interruptible_sleep() {
    local duration="$1"
    sleep "$duration" &
    SLEEP_PID=$!
    wait "$SLEEP_PID" 2>/dev/null || true
    SLEEP_PID=""
}

### Execution

# Remove stale pid file
rm -f "$PID_FILE"

# Start vcontrold
echo "Starting vcontrold..."
if [ ! -f /config/vcontrold.xml ]; then
    echo "Error: /config/vcontrold.xml not found!"
    exit 1
fi

# Change to config directory to ensure relative includes work
cd /config

# Start vcontrold in background
if [ "${DEBUG}" = true ]; then
    echo "Debug mode enabled"
    vcontrold -n -x vcontrold.xml --verbose --debug &
else
    vcontrold -n -x vcontrold.xml &
fi
PID=$!
echo "$PID" > "$PID_FILE"

sleep 2
if ! kill -0 "$PID" 2>/dev/null; then
    echo "vcontrold crashed on startup."
    exit 1
fi

# Revert to app directory
cd /app

# Wait for vcontrold to be ready (checking port availability)
echo "Waiting for vcontrold to accept connections..."
MAX_RETRIES=30
count=0
while ! vclient -h "$VCONTROLD_HOST:$VCONTROLD_PORT" -c "version" >/dev/null 2>&1; do
    interruptible_sleep 1
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

        if [ "${DEBUG}" = true ]; then
            echo "Debug: Executing vclient for: $current_list"
        fi

        # Run vclient with error checking
        if ! response=$(vclient -h "$VCONTROLD_HOST:$VCONTROLD_PORT" -c "${current_list}" -j 2>/dev/null); then
            echo "Warning: vclient command failed for list: $current_list"
            return
        fi

        if [ "${DEBUG}" = true ]; then
            echo "Debug: vclient response: $response"
        fi

        # Parse and publish (accept plain numbers or objects with a nested value field)
        echo "$response" | jq -r 'to_entries[] | "\(.key) \(.value | (if type=="object" and has("value") then .value else . end))"' | while read -r cmd value; do
            MQTT_SUBTOPIC="command/${cmd}"
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
            interruptible_sleep "${INTERVAL:-60}"
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

        interruptible_sleep "${INTERVAL:-60}"
    done
else
    echo "MQTT: inactive"
    # Simple keepalive loop
    while true; do
        if ! kill -0 "$PID" 2>/dev/null; then
            echo "Error: vcontrold process died. Exiting."
            exit 1
        fi
        interruptible_sleep 60
    done
fi
