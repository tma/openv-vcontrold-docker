#!/bin/bash

# Helper utilities for MQTT env validation + mosquitto argument construction.
mqtt_require_env() {
    MQTT_HOST="${MQTT_HOST:-}"
    MQTT_PORT="${MQTT_PORT:-1883}"
    MQTT_TOPIC="${MQTT_TOPIC:-}"
    MQTT_USER="${MQTT_USER:-}"
    MQTT_PASSWORD="${MQTT_PASSWORD:-}"

    if [[ -z "$MQTT_HOST" ]] || [[ -z "$MQTT_TOPIC" ]]; then
        echo "Error: MQTT_HOST or MQTT_TOPIC is not set" >&2
        exit 1
    fi
}

mosquitto_arguments() {
    local host="$1"
    local port="${2:-1883}"
    local user="$3"
    local password="$4"

    local args=(
        -u "$user" -P "$password"
        -h "$host" -p "$port"
    )

    if [[ "${MQTT_TLS:-false}" = true ]]; then
        [[ -n "${MQTT_CAFILE:-}" ]] && args+=(--cafile "${MQTT_CAFILE}")
        [[ -n "${MQTT_CAPATH:-}" ]] && args+=(--capath "${MQTT_CAPATH}")
        [[ -n "${MQTT_CERTFILE:-}" ]] && args+=(--cert "${MQTT_CERTFILE}")
        [[ -n "${MQTT_KEYFILE:-}" ]] && args+=(--key "${MQTT_KEYFILE}")
        [[ -n "${MQTT_TLS_VERSION:-}" ]] && args+=(--tls-version "${MQTT_TLS_VERSION}")
        [[ "${MQTT_TLS_INSECURE:-false}" = true ]] && args+=(--insecure)
    fi

    printf '%s
' "${args[@]}"
}
