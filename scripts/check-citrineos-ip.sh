#!/bin/bash

# =============================================================================
# MicroOCPP Simulator - CitrineOS IP check for container restarts
# =============================================================================
# This script runs on container startup. It checks whether the stored
# CitrineOS IP is still current and updates the config if needed.
# =============================================================================

is_valid_ipv4() {
    echo "$1" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
}

# Retries with backoff to handle race conditions during Docker engine restarts.
MAX_RETRIES=5
RETRY_DELAY=3

echo "[IP-Check] Checking CitrineOS IP configuration..."

if [ "$OCPP_VERSION" = "1.6" ]; then
    CONFIG_FILE="/MicroOcppSimulator/mo_store/ws-conn.jsn"
    PORT="8092"
    echo "[IP-Check] Detected OCPP 1.6 simulator"
elif [ "$OCPP_VERSION" = "2.0.1" ]; then
    CONFIG_FILE="/MicroOcppSimulator/mo_store/ws-conn-v201.jsn"
    PORT="8082"
    echo "[IP-Check] Detected OCPP 2.0.1 simulator"
else
    echo "[IP-Check] Unknown OCPP version: $OCPP_VERSION"
    exit 0
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "[IP-Check] Config file not found: $CONFIG_FILE"
    if [ -f "/configure-citrineos.sh" ]; then
        echo "[IP-Check] Running full configuration..."
        bash /configure-citrineos.sh
        echo "[IP-Check] Configuration finished"
    else
        echo "[IP-Check] configure-citrineos.sh is not available"
    fi
    exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "[IP-Check] Docker CLI is not available inside the container"
    echo "[IP-Check] IP check finished"
    exit 0
fi

CURRENT_CITRINEOS_IP=""

for attempt in $(seq 1 "$MAX_RETRIES"); do
    RAW_IP=$(
        docker inspect fenexity-citrineos \
            --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
            2>/dev/null
    )

    if [ -z "$RAW_IP" ] || [ "$RAW_IP" = "null" ]; then
        RAW_IP=$(
            docker inspect citrineos \
                --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
                2>/dev/null
        )
    fi

    if is_valid_ipv4 "$RAW_IP"; then
        CURRENT_CITRINEOS_IP="$RAW_IP"
        break
    fi

    if [ "$attempt" -lt "$MAX_RETRIES" ]; then
        echo "[IP-Check] CitrineOS is not ready yet "
        echo "($attempt/$MAX_RETRIES, response: '$RAW_IP'). Waiting ${RETRY_DELAY}s..."
        sleep "$RETRY_DELAY"
    fi
done

if [ -z "$CURRENT_CITRINEOS_IP" ]; then
    echo "[IP-Check] Could not determine a valid CitrineOS IP after "
    echo "$MAX_RETRIES attempts (last response: '$RAW_IP')"
    echo "[IP-Check] Keeping the existing configuration"
    echo "[IP-Check] IP check finished"
    exit 0
fi

echo "[IP-Check] Current CitrineOS IP: $CURRENT_CITRINEOS_IP"

CONFIG_IP=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$CONFIG_FILE" | head -1)

if [ -z "$CONFIG_IP" ]; then
    echo "[IP-Check] No IP address found in config file"
    echo "[IP-Check] IP check finished"
    exit 0
fi

echo "[IP-Check] Configured IP: $CONFIG_IP"

if [ "$CURRENT_CITRINEOS_IP" = "$CONFIG_IP" ]; then
    echo "✅ [IP-Check] IP address is up to date"
else
    echo "[IP-Check] IP changed: $CONFIG_IP -> $CURRENT_CITRINEOS_IP"
    echo "[IP-Check] Updating configuration..."
    sed -i "s/$CONFIG_IP/$CURRENT_CITRINEOS_IP/g" "$CONFIG_FILE"
    echo "✅ [IP-Check] IP address updated successfully"
fi

echo "[IP-Check] IP check finished"
