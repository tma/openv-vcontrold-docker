#!/bin/bash
set -euo pipefail

sleep 3

### config

# the max command length vclient can accept (see vcontrold PR #135)
MAX_LENGTH=512

# the usb device
USB_DEVICE=/dev/vitocal
echo "Device ${USB_DEVICE}"

### execution

# run vcontrold with the config; logging is controlled by /config/vcontrold.xml
vcontrold -x /config/vcontrold.xml -P /tmp/vcontrold.pid

status=$?
pid=$(pidof vcontrold || true)

if [ $status -ne 0 ]; then
    echo "Failed to start vcontrold"
fi

if [ "${MQTTACTIVE:-false}" = true ]; then
    echo "vcontrold started (PID $pid)"
    echo "MQTT: active (var = $MQTTACTIVE)"
    echo "Update interval: $INTERVAL sec"
    echo "Commands: $COMMANDS"

    # start request/response handler in background
    # /app/subscribe.sh &

    # Run vclient on a sublist of commands and publish one plain value per command
    execute_vclient_and_publish_values() {
        local current_list=$1
        local response

        # vclient JSON (short form, one object with keys for each command)
        response=$(vclient -h 127.0.0.1:3002 -c "${current_list}" -j)

        # response is e.g. { "CMD1": {...}, "CMD2": {...} }
        # Publish each CMD's .value as a plain payload
        for cmd in $(echo "$response" | jq -r 'keys[]'); do
            # Extract just the "value" field (string/number/boolean)
            # Adjust this path if your vclient JSON differs
            cmd_value=$(echo "$response" | jq -r --arg key "$cmd" '.[$key].value')

            # Topic suffix: scheduled_poll/<command-name>
            MQTT_SUBTOPIC="info/${cmd}"

            # Publish plain value to MQTT
            /app/publish.sh "$MQTT_SUBTOPIC" <<< "$cmd_value"
        done
    }

    while true; do
        sublist=""

        IFS=','  # Split COMMANDS by comma
        for cmd in $COMMANDS; do

            # First command in a new sublist
            if [[ ${#sublist} -eq 0 ]]; then
                sublist="$cmd"
            # Can still append without exceeding max
            elif (( ${#sublist} + ${#cmd} + 1 <= MAX_LENGTH )); then
                sublist+=",${cmd}"
            else
                # Execute current sublist and reset
                execute_vclient_and_publish_values "$sublist"
                sublist="$cmd"
            fi

        done

        # Execute the last sublist if it exists
        if [[ -n $sublist ]]; then
            execute_vclient_and_publish_values "$sublist"
        fi

        if [ -e /tmp/vcontrold.pid ]; then
            :
        else
            echo "vcontrold.pid doesn't exist. exit with code 0"
            exit 0
        fi

        sleep "$INTERVAL"
    done
else
    echo "vcontrold started (PID $pid)"
    echo "MQTT: inactive (var = $MQTTACTIVE)"
    echo "PID: $pid"

    while sleep 600; do
        if [ -e /tmp/vcontrold.pid ]; then
            :
        else
            echo "vcontrold.pid doesn't exist. exit with code 0"
            exit 0
        fi
    done
fi
