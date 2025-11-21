#!/bin/bash
set -euo pipefail

# This script subscribes to a MQTT topic using mosquitto_sub.
# On each message received, it sends the payload as a command to vclient
# and publishes the JSON response back to MQTT.

while true  # Keep an infinite loop to reconnect when connection lost/broker unavailable
do
    mosquitto_sub \
        -u "$MQTTUSER" -P "$MQTTPASSWORD" \
        -h "$MQTTHOST" -p "$MQTTPORT" \
        -t "$MQTTTOPIC/request" \
        -I "VCONTROLD-SUB" \
    | while read -r payload
    do
        # payload is a vclient command string
        response=$(vclient -h 127.0.0.1:3002 -c "${payload}" -j)

        # For request/response, keep JSON – caller likely wants structure
        mosquitto_pub \
            -u "$MQTTUSER" -P "$MQTTPASSWORD" \
            -h "$MQTTHOST" -p "$MQTTPORT" \
            -t "$MQTTTOPIC/response" \
            -m "$response" \
            -x 120 -c --id "VCONTROLD-PUB" -V "mqttv5"
    done

    sleep 10  # Wait 10 seconds until reconnection
done
