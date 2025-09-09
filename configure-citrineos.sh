#!/bin/bash

# =============================================================================
# Fenexity CSMS Platform - MicroOCPP CitrineOS Konfiguration (Hybrid-Ansatz)
# =============================================================================
# Automatische Konfiguration der MicroOCPP-Simulatoren für korrekte 
# Dual-Protocol-Verbindung mit CitrineOS
#
# HYBRID-ANSATZ:
# - Konfigurationsdateien verwenden Service-Namen (wartungsfreundlich)
# - Zur Runtime wird Service-Name durch aktuelle IP ersetzt (Mongoose-kompatibel)
#
# OCPP 1.6  → Port 8092 (fenexity-citrineos → aktuelle IP) - Funktionaler Workaround 
# OCPP 2.0.1 → Port 8082 (fenexity-citrineos → aktuelle IP)
# =============================================================================

echo "🔧 Konfiguriere MicroOCPP-Simulatoren für CitrineOS (Hybrid-Ansatz)..."

# Service-Name (wartungsfreundlich in Source Control)
CITRINEOS_SERVICE="${CITRINEOS_SERVICE:-fenexity-citrineos}"

# Dynamische IP-Ermittlung zur Runtime (Mongoose-kompatibel)
echo "🔍 Ermittle aktuelle IP von Container: $CITRINEOS_SERVICE..."

# Versuche verschiedene Methoden, um die IP zu finden
CITRINEOS_IP=""

# Methode 1: Robuste Docker-Format-Methode
CITRINEOS_IP=$(docker inspect "$CITRINEOS_SERVICE" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)

# Methode 2: Fallback mit "citrineos" Alias
if [ -z "$CITRINEOS_IP" ] || [ "$CITRINEOS_IP" = "null" ]; then
    echo "🔍 Fallback: Versuche mit 'citrineos' Alias..."
    CITRINEOS_IP=$(docker inspect "citrineos" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
fi

# Methode 3: Legacy grep-Methode als letzter Fallback
if [ -z "$CITRINEOS_IP" ] || [ "$CITRINEOS_IP" = "null" ]; then
    echo "🔍 Fallback: Versuche legacy IP-Ermittlung..."
    CITRINEOS_IP=$(docker inspect "$CITRINEOS_SERVICE" 2>/dev/null | grep '"IPAddress"' | grep -v '""' | head -1 | sed 's/.*"IPAddress": "\([^"]*\)".*/\1/')
fi

# Validation: IP-Adresse prüfen
if [ -z "$CITRINEOS_IP" ] || [ "$CITRINEOS_IP" = "null" ]; then
    echo "❌ Fehler: CitrineOS Container IP konnte nicht ermittelt werden!"
    echo "   Container läuft: $(docker ps --filter "name=$CITRINEOS_SERVICE" --format '{{.Status}}')"
    exit 1
fi

echo "✅ CitrineOS Container gefunden: $CITRINEOS_SERVICE → $CITRINEOS_IP"

OCPP16_PORT="8092"  # Funktionaler OCPP 1.6 Port (Workaround für Protocol-Mismatch auf 8081)
OCPP201_PORT="8082"

# =============================================================================
# OCPP 1.6 Simulator Konfiguration
# =============================================================================

echo "📝 Konfiguriere OCPP 1.6 Simulator (charger-1.6)..."

# Store-Verzeichnis erstellen falls nicht vorhanden
mkdir -p "$(dirname "$0")/mo_store_v16"

# OCPP 1.6 WebSocket-Verbindung (legacy format)
cat > "$(dirname "$0")/mo_store_v16/ws-conn.jsn" << EOF
{
  "head": {
    "content-type": "ocpp_config_file",
    "version": "2.0"
  },
  "configurations": [
    {
      "type": "string",
      "key": "Cst_BackendUrl",
      "value": "ws://${CITRINEOS_IP}:${OCPP16_PORT}/charger-1.6"
    },
    {
      "type": "string",
      "key": "Cst_ChargeBoxId",
      "value": "charger-1.6"
    },
    {
      "type": "string",
      "key": "AuthorizationKey",
      "value": ""
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

# OCPP 1.6 WebSocket-Verbindung (OCPP 2.0.1 format for compatibility)
cat > "$(dirname "$0")/mo_store_v16/ws-conn-v201.jsn" << EOF
{
  "variables": [
    {
      "component": "SecurityCtrlr",
      "name": "CsmsUrl",
      "valActual": "ws://${CITRINEOS_IP}:${OCPP16_PORT}/charger-1.6"
    },
    {
      "component": "SecurityCtrlr",
      "name": "Identity",
      "valActual": "charger-1.6"
    },
    {
      "component": "SecurityCtrlr",
      "name": "BasicAuthPassword",
      "valActual": ""
    }
  ]
}
EOF

echo "✅ OCPP 1.6 Simulator konfiguriert: ws://${CITRINEOS_IP}:${OCPP16_PORT}/charger-1.6"

# =============================================================================
# OCPP 2.0.1 Simulator Konfiguration  
# =============================================================================

echo "📝 Konfiguriere OCPP 2.0.1 Simulator (charger-201)..."

# Store-Verzeichnis erstellen falls nicht vorhanden
mkdir -p "$(dirname "$0")/mo_store_v201"

# OCPP 2.0.1 WebSocket-Verbindung - MIT KORREKTER AUTH-KONFIGURATION
cat > "$(dirname "$0")/mo_store_v201/ws-conn-v201.jsn" << EOF
{
  "variables": [
    {
      "component": "SecurityCtrlr",
      "name": "CsmsUrl",
      "valActual": "ws://${CITRINEOS_IP}:${OCPP201_PORT}/charger-201"
    },
    {
      "component": "SecurityCtrlr",
      "name": "Identity",
      "valActual": "charger-201"
    },
    {
      "component": "SecurityCtrlr",
      "name": "BasicAuthPassword",
      "valActual": "fenexity_test_2025"
    }
  ]
}
EOF

# LEGACY ws-conn.jsn mit AuthorizationKey für Fallback-Kompatibilität
cat > "$(dirname "$0")/mo_store_v201/ws-conn.jsn" << EOF
{
  "head": {
    "content-type": "ocpp_config_file",
    "version": "2.0"
  },
  "configurations": [
    {
      "type": "string",
      "key": "Cst_BackendUrl",
      "value": "ws://${CITRINEOS_IP}:${OCPP201_PORT}/charger-201"
    },
    {
      "type": "string",
      "key": "Cst_ChargeBoxId",
      "value": "charger-201"
    },
    {
      "type": "string",
      "key": "AuthorizationKey",
      "value": "fenexity_test_2025"
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

echo "✅ OCPP 2.0.1 Simulator konfiguriert: ws://${CITRINEOS_IP}:${OCPP201_PORT}/charger-201 (Auth: fenexity_test_2025)"

# =============================================================================
# Konfigurationsvalidierung
# =============================================================================

echo "🔍 Validiere Konfiguration..."

# Überprüfe OCPP 1.6 Konfiguration
if grep -q "ws://${CITRINEOS_IP}:${OCPP16_PORT}/charger-1.6" "$(dirname "$0")/mo_store_v16/ws-conn.jsn"; then
    echo "✅ OCPP 1.6 Backend-URL korrekt"
else
    echo "❌ OCPP 1.6 Backend-URL fehlerhaft"
    exit 1
fi

# Überprüfe OCPP 2.0.1 Konfiguration  
if grep -q "ws://${CITRINEOS_IP}:${OCPP201_PORT}/charger-201" "$(dirname "$0")/mo_store_v201/ws-conn-v201.jsn"; then
    echo "✅ OCPP 2.0.1 CSMS-URL korrekt"
else
    echo "❌ OCPP 2.0.1 CSMS-URL fehlerhaft"
    exit 1
fi

echo ""
echo "🎯 MicroOCPP-Konfiguration erfolgreich abgeschlossen!"
echo ""
echo "📋 Konfigurationsübersicht:"
echo "   🔌 OCPP 1.6  (charger-1.6):  ws://${CITRINEOS_IP}:${OCPP16_PORT}/charger-1.6"
echo "   🔌 OCPP 2.0.1 (charger-201): ws://${CITRINEOS_IP}:${OCPP201_PORT}/charger-201 + Auth"
echo ""
echo "🚀 Die Simulatoren sind bereit für die Verbindung mit CitrineOS!" 

# =============================================================================
# SCHRITT 4: BasicAuth-Passwort in CitrineOS-Datenbank registrieren
# =============================================================================

echo "🔐 Registriere BasicAuth-Passwort für charger-201 in CitrineOS..."

# BasicAuth-Key für OCPP 2.0.1
BASICAUTH_PASSWORD="fenexity_test_2025"

# Erstelle PBKDF2-Hash im CitrineOS-Format mit Node.js
echo "🔧 Erstelle PBKDF2-Hash für BasicAuth..."
PBKDF2_HASH=$(docker exec fenexity-citrineos node -e "
const crypto = require('crypto');
const password = '$BASICAUTH_PASSWORD';
const salt = crypto.randomBytes(16).toString('hex');
const hash = crypto.pbkdf2Sync(password, salt, 1000, 64, 'sha512').toString('hex');
const final = \`PBKDF2:1000:64:sha512:\${salt}:\${hash}\`;
console.log(final);
")

if [ -z "$PBKDF2_HASH" ]; then
    echo "❌ Fehler: PBKDF2-Hash konnte nicht erstellt werden!"
    exit 1
fi

echo "✅ PBKDF2-Hash erstellt: ${PBKDF2_HASH:0:30}..."

# SQL-Query um BasicAuth-Passwort in CitrineOS zu registrieren
# WICHTIG: Components und Variables werden manuell erstellt da CitrineOS sie nicht automatisch lädt
cat << EOF | docker exec -i fenexity-postgres psql -U citrine -d citrine
-- Erstelle SecurityCtrlr Component (falls nicht existiert)
INSERT INTO "Components" (name, instance, "createdAt", "updatedAt")
SELECT 'SecurityCtrlr', NULL, NOW(), NOW()
WHERE NOT EXISTS (
    SELECT 1 FROM "Components" 
    WHERE name = 'SecurityCtrlr' AND instance IS NULL
);

-- Erstelle BasicAuthPassword Variable (falls nicht existiert)
INSERT INTO "Variables" (name, instance, "createdAt", "updatedAt")
SELECT 'BasicAuthPassword', NULL, NOW(), NOW()
WHERE NOT EXISTS (
    SELECT 1 FROM "Variables" 
    WHERE name = 'BasicAuthPassword' AND instance IS NULL
);

-- Hole Component- und Variable-IDs
DO \$\$
DECLARE
    component_id INTEGER;
    variable_id INTEGER;
BEGIN
    -- Hole SecurityCtrlr Component ID
    SELECT id INTO component_id 
    FROM "Components" 
    WHERE name = 'SecurityCtrlr' AND instance IS NULL;
    
    -- Hole BasicAuthPassword Variable ID
    SELECT id INTO variable_id 
    FROM "Variables" 
    WHERE name = 'BasicAuthPassword' AND instance IS NULL;
    
    -- Lösche existierende BasicAuth-Einträge für charger-201
    DELETE FROM "VariableAttributes" 
    WHERE "stationId" = 'charger-201' 
      AND "componentId" = component_id 
      AND "variableId" = variable_id;
    
    -- Füge neuen BasicAuth-Eintrag hinzu
    INSERT INTO "VariableAttributes" (
        "stationId",
        "componentId", 
        "variableId",
        "dataType",
        "type",
        "value",
        "mutability",
        "persistent",
        "constant",
        "generatedAt",
        "createdAt",
        "updatedAt"
    )
    VALUES (
        'charger-201',
        component_id,
        variable_id,
        'passwordString',
        'Actual',
        '$PBKDF2_HASH',
        'WriteOnly',
        true,
        false,
        NOW(),
        NOW(),
        NOW()
    );
END \$\$;
EOF

if [ $? -eq 0 ]; then
    # Validiere dass das BasicAuth korrekt gespeichert wurde
    BASICAUTH_COUNT=$(docker exec -i fenexity-postgres psql -U citrine -d citrine -t -c "
        SELECT COUNT(*) 
        FROM \"VariableAttributes\" va 
        JOIN \"Components\" c ON va.\"componentId\" = c.id 
        JOIN \"Variables\" v ON va.\"variableId\" = v.id 
        WHERE va.\"stationId\" = 'charger-201' 
          AND c.name = 'SecurityCtrlr' 
          AND v.name = 'BasicAuthPassword';" | tr -d ' ')
    
    if [ "$BASICAUTH_COUNT" = "1" ]; then
        echo "✅ BasicAuth-Passwort für charger-201 erfolgreich registriert!"
        echo "🔑 Passwort: $BASICAUTH_PASSWORD (PBKDF2-gehashed)"
        echo "🎯 Datenbank-Validation: $BASICAUTH_COUNT Eintrag gefunden"
    else
        echo "❌ BasicAuth-Registrierung fehlgeschlagen - $BASICAUTH_COUNT Einträge gefunden (erwartet: 1)"
        exit 1
    fi
else
    echo "⚠️ BasicAuth-Registrierung fehlgeschlagen"
    exit 1
fi 