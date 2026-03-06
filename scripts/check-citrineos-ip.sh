#!/bin/bash

# =============================================================================
# Fenexity CSMS Platform - CitrineOS IP-Check für Container-Neustarts
# =============================================================================
# Dieses Script läuft bei jedem Container-Start und prüft, ob die CitrineOS-IP
# in den Konfigurationsdateien noch aktuell ist. Falls nicht, wird sie aktualisiert.
# 
# Verwendung: Als Startup-Script in den Simulator-Containern
# =============================================================================

is_valid_ipv4() {
    echo "$1" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
}

# Retries with backoff to handle race conditions during Docker engine restarts
MAX_RETRIES=5
RETRY_DELAY=3

echo "🔍 [IP-Check] Prüfe CitrineOS-IP-Konfiguration..."

if [ "$OCPP_VERSION" = "1.6" ]; then
    CONFIG_FILE="/MicroOcppSimulator/mo_store/ws-conn.jsn"
    PORT="8092"
    echo "🔌 [IP-Check] OCPP 1.6 Simulator erkannt"
elif [ "$OCPP_VERSION" = "2.0.1" ]; then
    CONFIG_FILE="/MicroOcppSimulator/mo_store/ws-conn-v201.jsn"
    PORT="8082"
    echo "🔌 [IP-Check] OCPP 2.0.1 Simulator erkannt"
else
    echo "❌ [IP-Check] Unbekannte OCPP-Version: $OCPP_VERSION"
    exit 0
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "⚠️  [IP-Check] Konfigurationsdatei nicht gefunden: $CONFIG_FILE"
    if [ -f "/configure-citrineos.sh" ]; then
        echo "🔧 [IP-Check] Führe vollständige Konfiguration aus..."
        bash /configure-citrineos.sh
        echo "✅ [IP-Check] Konfiguration abgeschlossen"
    else
        echo "❌ [IP-Check] configure-citrineos.sh nicht verfügbar"
    fi
    exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "⚠️  [IP-Check] Docker CLI nicht verfügbar im Container"
    echo "🎯 [IP-Check] IP-Prüfung abgeschlossen"
    exit 0
fi

CURRENT_CITRINEOS_IP=""

for attempt in $(seq 1 $MAX_RETRIES); do
    RAW_IP=$(docker inspect fenexity-citrineos --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)

    if [ -z "$RAW_IP" ] || [ "$RAW_IP" = "null" ]; then
        RAW_IP=$(docker inspect citrineos --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
    fi

    if is_valid_ipv4 "$RAW_IP"; then
        CURRENT_CITRINEOS_IP="$RAW_IP"
        break
    fi

    if [ "$attempt" -lt "$MAX_RETRIES" ]; then
        echo "⏳ [IP-Check] CitrineOS noch nicht bereit (Versuch $attempt/$MAX_RETRIES, Antwort: '$RAW_IP'). Warte ${RETRY_DELAY}s..."
        sleep "$RETRY_DELAY"
    fi
done

if [ -z "$CURRENT_CITRINEOS_IP" ]; then
    echo "⚠️  [IP-Check] Konnte keine gültige CitrineOS-IP ermitteln nach $MAX_RETRIES Versuchen (letzte Antwort: '$RAW_IP')"
    echo "⚠️  [IP-Check] Behalte bestehende Konfiguration bei"
    echo "🎯 [IP-Check] IP-Prüfung abgeschlossen"
    exit 0
fi

echo "🔍 [IP-Check] Aktuelle CitrineOS-IP: $CURRENT_CITRINEOS_IP"

CONFIG_IP=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$CONFIG_FILE" | head -1)

if [ -z "$CONFIG_IP" ]; then
    echo "⚠️  [IP-Check] Keine IP in Konfigurationsdatei gefunden"
    echo "🎯 [IP-Check] IP-Prüfung abgeschlossen"
    exit 0
fi

echo "📝 [IP-Check] Konfigurierte IP: $CONFIG_IP"

if [ "$CURRENT_CITRINEOS_IP" = "$CONFIG_IP" ]; then
    echo "✅ [IP-Check] IP-Adresse ist aktuell"
else
    echo "🔄 [IP-Check] IP-Adresse hat sich geändert: $CONFIG_IP → $CURRENT_CITRINEOS_IP"
    echo "🔧 [IP-Check] Aktualisiere Konfiguration..."
    sed -i "s/$CONFIG_IP/$CURRENT_CITRINEOS_IP/g" "$CONFIG_FILE"
    echo "✅ [IP-Check] IP-Adresse erfolgreich aktualisiert"
fi

echo "🎯 [IP-Check] IP-Prüfung abgeschlossen"
