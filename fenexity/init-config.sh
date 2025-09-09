#!/bin/bash

# =============================================================================
# Fenexity CSMS Platform - MicroOCPP Simulator Konfiguration
# =============================================================================
# Script: init-config.sh
# Zweck: Setzt automatisch die korrekten WebSocket-URLs und OCPP-Versionen nach Container-Start

echo "🔧 MicroOCPP Simulator Konfiguration wird initialisiert..."

# Warte auf Container-Startup
echo "⏱️ Warte 10 Sekunden für Container-Startup..."
sleep 10

# Hole CitrineOS Container IP
CITRINE_IP=$(docker inspect fenexity-citrineos | jq -r '.[0].NetworkSettings.Networks."fenexity-csms".IPAddress')
if [ -z "$CITRINE_IP" ] || [ "$CITRINE_IP" = "null" ]; then
    echo "❌ CitrineOS Container nicht gefunden!"
    exit 1
fi
echo "🔍 CitrineOS gefunden unter IP: $CITRINE_IP"

# Funktion: WebSocket-Konfiguration setzen
set_websocket_config() {
    local container_name=$1
    local backend_url=$2
    local charger_id=$3
    
    echo "🔧 Konfiguriere WebSocket für $container_name..."
    
    # Setze das authorizationKey basierend auf dem Container
    local auth_key=""
    if [ "$container_name" = "microocpp-sim-v201" ]; then
        auth_key="fenexity_test_2025"
        echo "🔑 Setze BasicAuth-Password für OCPP 2.0.1: $auth_key"
    fi
    
    # Standard ws-conn.jsn Konfiguration
    local config=$(cat <<EOF
{
  "head": {
    "content-type": "ocpp_config_file",
    "version": "2.0"
  },
  "configurations": [
    {
      "type": "string",
      "key": "Cst_BackendUrl",
      "value": "$backend_url"
    },
    {
      "type": "string",
      "key": "Cst_ChargeBoxId",
      "value": "$charger_id"
    },
    {
      "type": "string",
      "key": "AuthorizationKey",
      "value": "$auth_key"
    },
    {
      "type": "int",
      "key": "WebSocketPingInterval",
      "value": 5
    },
    {
      "type": "int",
      "key": "Cst_ReconnectInterval",
      "value": 10
    },
    {
      "type": "int",
      "key": "Cst_StaleTimeout",
      "value": 300
    }
  ]
}
EOF
)
    
    # OCPP 2.0.1 spezifische ws-conn-v201.jsn Konfiguration - MIT KORREKTUREN
    local config_v201=$(cat <<EOF
{
  "variables": [
    {
      "component": "SecurityCtrlr",
      "name": "CsmsUrl",
      "valActual": "$backend_url"
    },
    {
      "component": "SecurityCtrlr",
      "name": "Identity",
      "valActual": "$charger_id"
    },
    {
      "component": "SecurityCtrlr",
      "name": "BasicAuthPassword",
      "valActual": "$auth_key"
    }
  ]
}
EOF
)

    # Schreibe Standard-Konfiguration
    echo "$config" | docker exec -i $container_name sh -c 'cat > /MicroOcppSimulator/mo_store/ws-conn.jsn'
    
    # Schreibe OCPP 2.0.1-spezifische Konfiguration
    echo "$config_v201" | docker exec -i $container_name sh -c 'cat > /MicroOcppSimulator/mo_store/ws-conn-v201.jsn'
    
    echo "✅ $container_name WebSocket konfiguriert: $backend_url -> $charger_id (Auth: $auth_key)"
}

# Funktion: OCPP-Version setzen
set_ocpp_version() {
    local container_name=$1
    local version=$2
    
    echo "🔧 Setze OCPP-Version für $container_name auf $version..."
    
    local config=$(cat <<EOF
{
  "head": {
    "content-type": "ocpp_config_file",
    "version": "2.0"
  },
  "configurations": [
    {
      "type": "string",
      "key": "OcppVersion",
      "value": "$version"
    },
    {
      "type": "bool",
      "key": "evPlugged_cId_1",
      "value": false
    },
    {
      "type": "bool",
      "key": "evsePlugged_cId_1",
      "value": false
    },
    {
      "type": "bool",
      "key": "evReady_cId_1",
      "value": false
    },
    {
      "type": "bool",
      "key": "evseReady_cId_1",
      "value": false
    },
    {
      "type": "bool",
      "key": "evPlugged_cId_2",
      "value": false
    },
    {
      "type": "bool",
      "key": "evsePlugged_cId_2",
      "value": false
    },
    {
      "type": "bool",
      "key": "evReady_cId_2",
      "value": false
    },
    {
      "type": "bool",
      "key": "evseReady_cId_2",
      "value": false
    }
  ]
}
EOF
)
    
    echo "$config" | docker exec -i $container_name sh -c 'cat > /MicroOcppSimulator/mo_store/simulator.jsn'
    echo "✅ $container_name OCPP-Version gesetzt auf $version"
}

# Funktion: Frontend-API-Mock einrichten
setup_frontend_api_mock() {
    local container_name=$1
    
    echo "🌐 Richte Frontend-API-Mock für $container_name ein..."
    
    # Einfacher API-Mock für /api/station
    local api_mock=$(cat <<'EOF'
{
  "station": {
    "id": "test-station",
    "status": "available"
  }
}
EOF
)
    
    docker exec $container_name sh -c 'mkdir -p /MicroOcppSimulator/public/api'
    echo "$api_mock" | docker exec -i $container_name sh -c 'cat > /MicroOcppSimulator/public/api/station'
    
    echo "✅ $container_name Frontend-API-Mock eingerichtet"
}

# Konfiguriere beide Container mit KORREKTEN URLs
set_websocket_config microocpp-sim-v16 "ws://$CITRINE_IP:8092/charger-1.6" "charger-1.6"
set_ocpp_version microocpp-sim-v16 "1.6"
setup_frontend_api_mock microocpp-sim-v16

# FIX: OCPP 2.0.1 URL muss Charger-ID enthalten für korrekte Authentifizierung
set_websocket_config microocpp-sim-v201 "ws://$CITRINE_IP:8082/charger-201" "charger-201"
set_ocpp_version microocpp-sim-v201 "2.0.1"
setup_frontend_api_mock microocpp-sim-v201

echo ""
echo "🔄 Container werden neugestartet für Konfigurationsübernahme..."
docker restart microocpp-sim-v16 microocpp-sim-v201

echo "⏱️ Warte 15 Sekunden für Container-Neustart..."
sleep 15

echo ""
echo "🔑 Setze OCPP 2.0.1 BasicAuth über API (Fallback-Methode)..."
# Setze authorizationKey für OCPP 2.0.1 über API (persistent)
curl -s -X POST http://localhost:8002/api/websocket \
    -H "Content-Type: application/json" \
    -d '{"authorizationKey": "fenexity_test_2025"}' > /dev/null 2>&1
echo "✅ BasicAuth-Password für charger-201 über API gesetzt (falls JSON-Konfiguration nicht ausreicht)"

echo ""
echo "🎯 Konfiguration abgeschlossen!"
echo "🔍 Verifikation:"

echo "OCPP 1.6:"
docker exec microocpp-sim-v16 cat /MicroOcppSimulator/mo_store/ws-conn.jsn | jq '.configurations[] | select(.key=="Cst_BackendUrl" or .key=="Cst_ChargeBoxId" or .key=="AuthorizationKey")'

echo ""
echo "OCPP 2.0.1:"
docker exec microocpp-sim-v201 cat /MicroOcppSimulator/mo_store/ws-conn.jsn | jq '.configurations[] | select(.key=="Cst_BackendUrl" or .key=="Cst_ChargeBoxId" or .key=="AuthorizationKey")'

echo ""
echo "OCPP 2.0.1 Security Configuration:"
docker exec microocpp-sim-v201 cat /MicroOcppSimulator/mo_store/ws-conn-v201.jsn | jq '.variables[] | select(.name=="CsmsUrl" or .name=="Identity" or .name=="BasicAuthPassword")'

echo ""
echo "🌐 Frontend-Zugriff:"
echo "OCPP 1.6: http://localhost:8001 (Charger ID: charger-1.6)"
echo "OCPP 2.0.1: http://localhost:8002 (Charger ID: charger-201, Auth: fenexity_test_2025)"

echo ""
echo "✅ MicroOCPP Simulator Konfiguration abgeschlossen!" 