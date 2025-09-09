#!/bin/bash

# =============================================================================
# Fenexity CSMS Platform - CitrineOS IP-Check für Container-Neustarts
# =============================================================================
# Dieses Script läuft bei jedem Container-Start und prüft, ob die CitrineOS-IP
# in den Konfigurationsdateien noch aktuell ist. Falls nicht, wird sie aktualisiert.
# 
# Verwendung: Als Startup-Script in den Simulator-Containern
# =============================================================================

echo "🔍 [IP-Check] Prüfe CitrineOS-IP-Konfiguration..."

# Aktueller Container-Typ ermitteln
if [ "$OCPP_VERSION" = "1.6" ]; then
    CONFIG_FILE="/MicroOcppSimulator/mo_store/ws-conn.jsn"
    CHARGER_ID="charger-1.6"
    PORT="8092"
    echo "🔌 [IP-Check] OCPP 1.6 Simulator erkannt"
elif [ "$OCPP_VERSION" = "2.0.1" ]; then
    CONFIG_FILE="/MicroOcppSimulator/mo_store/ws-conn-v201.jsn"
    CHARGER_ID="charger-201"
    PORT="8082"
    echo "🔌 [IP-Check] OCPP 2.0.1 Simulator erkannt"
else
    echo "❌ [IP-Check] Unbekannte OCPP-Version: $OCPP_VERSION"
    exit 0  # Nicht kritisch, Simulator kann trotzdem starten
fi

# Prüfe ob Konfigurationsdatei existiert
if [ ! -f "$CONFIG_FILE" ]; then
    echo "⚠️  [IP-Check] Konfigurationsdatei nicht gefunden: $CONFIG_FILE"
    echo "🔧 [IP-Check] Führe vollständige Konfiguration aus..."
    
    # Fallback: Vollständige Konfiguration ausführen
    if [ -f "/configure-citrineos.sh" ]; then
        bash /configure-citrineos.sh
    else
        echo "❌ [IP-Check] configure-citrineos.sh nicht verfügbar"
        exit 0
    fi
    
    echo "✅ [IP-Check] Konfiguration abgeschlossen"
    exit 0
fi

# Aktuelle CitrineOS-IP ermitteln (falls Docker-Socket verfügbar)
if command -v docker >/dev/null 2>&1; then
    CURRENT_CITRINEOS_IP=$(docker inspect fenexity-citrineos --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
    
    if [ -z "$CURRENT_CITRINEOS_IP" ] || [ "$CURRENT_CITRINEOS_IP" = "null" ]; then
        # Fallback: citrineos alias
        CURRENT_CITRINEOS_IP=$(docker inspect citrineos --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
    fi
    
    if [ -n "$CURRENT_CITRINEOS_IP" ] && [ "$CURRENT_CITRINEOS_IP" != "null" ]; then
        echo "🔍 [IP-Check] Aktuelle CitrineOS-IP: $CURRENT_CITRINEOS_IP"
        
        # IP aus Konfigurationsdatei extrahieren
        CONFIG_IP=$(grep -o '172\.[0-9]\+\.[0-9]\+\.[0-9]\+' "$CONFIG_FILE" | head -1)
        
        if [ -n "$CONFIG_IP" ]; then
            echo "📝 [IP-Check] Konfigurierte IP: $CONFIG_IP"
            
            # IP-Vergleich
            if [ "$CURRENT_CITRINEOS_IP" != "$CONFIG_IP" ]; then
                echo "🔄 [IP-Check] IP-Adresse hat sich geändert: $CONFIG_IP → $CURRENT_CITRINEOS_IP"
                echo "🔧 [IP-Check] Aktualisiere Konfiguration..."
                
                # IP in Konfigurationsdatei ersetzen
                sed -i "s/$CONFIG_IP/$CURRENT_CITRINEOS_IP/g" "$CONFIG_FILE"
                
                echo "✅ [IP-Check] IP-Adresse erfolgreich aktualisiert"
            else
                echo "✅ [IP-Check] IP-Adresse ist aktuell"
            fi
        else
            echo "⚠️  [IP-Check] Keine IP in Konfigurationsdatei gefunden"
        fi
    else
        echo "⚠️  [IP-Check] CitrineOS-Container nicht gefunden oder Docker nicht verfügbar"
    fi
else
    echo "⚠️  [IP-Check] Docker CLI nicht verfügbar im Container"
fi

echo "🎯 [IP-Check] IP-Prüfung abgeschlossen"
