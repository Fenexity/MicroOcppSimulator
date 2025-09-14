# MicroOCPP Simulator Templates

Dieses Verzeichnis enthält Template-Dateien für die automatische Generierung von mo_store-Konfigurationen für mehrere OCPP-Simulatoren.

## Template-Struktur

### mo_store_v16_template/
Template-Dateien für OCPP 1.6 Simulatoren. Diese werden als Basis für jeden generierten OCPP 1.6 Simulator verwendet.

### mo_store_v201_template/
Template-Dateien für OCPP 2.0.1 Simulatoren. Diese werden als Basis für jeden generierten OCPP 2.0.1 Simulator verwendet.

## Platzhalter

Die Template-Dateien verwenden folgende Platzhalter, die vom generate-simulators.sh Script automatisch ersetzt werden:

- `{{CHARGER_ID}}` - Eindeutige Charger-ID (z.B. charger-v16-001)
- `{{CSMS_URL}}` - WebSocket-URL zum CSMS/Backend
- `{{AUTH_PASSWORD}}` - BasicAuth-Passwort (nur OCPP 2.0.1)
- `{{CITRINEOS_IP}}` - IP-Adresse des CitrineOS Containers

## Automatische Generierung

Diese Templates werden NICHT manuell bearbeitet. Sie werden automatisch aus den aktuellen mo_store_v16/ und mo_store_v201/ Verzeichnissen generiert und mit Platzhaltern versehen.

Verwendung:
1. `./generate-simulators.sh` ausführen
2. Script kopiert aktuelle mo_store-Dateien in Templates
3. Script ersetzt spezifische Werte durch Platzhalter
4. Generierte Simulatoren verwenden diese Templates als Basis
