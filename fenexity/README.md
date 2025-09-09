# MicroOCPP Simulator - ARM64 & Multi-Architektur Integration

## 🎯 Übersicht

Vollständige Integration von MicroOCPP-Simulatoren in die Fenexity CSMS Platform mit:
- **Multi-Architektur-Unterstützung**: Intel/AMD64 und ARM64 (Apple Silicon)
- **Dual-Protokoll-Setup**: Separate Container für OCPP 1.6 und OCPP 2.0.1
- **CitrineOS-Integration**: Automatische Konfiguration für beide Protokollversionen
- **Flexible Make-Befehle**: Granulare Steuerung nach Architektur und Protokoll

## 🏗️ Architektur-Matrix

| Architektur | OCPP 1.6 Port | OCPP 2.0.1 Port | Make-Befehl |
|-------------|----------------|------------------|-------------|
| Intel/AMD64 | 8001 | 8002 | `make microocpp-start` |
| ARM64 | 8001 | 8002 | `make microocpp-start-arm64` |

## 🚀 Quick Start

### ARM64 (Apple Silicon) - Empfohlen
```bash
# Beide Simulatoren ARM64-optimiert starten
make microocpp-start-arm64

# Einzeln starten
make microocpp-start-v16-arm64    # Nur OCPP 1.6
make microocpp-start-v201-arm64   # Nur OCPP 2.0.1

# Status & Health-Checks
make microocpp-status-arm64
make microocpp-health-arm64
```

### Intel/AMD64 - Standard
```bash
# Beide Simulatoren starten
make microocpp-start

# Einzeln starten  
make microocpp-start-v16          # Nur OCPP 1.6
make microocpp-start-v201         # Nur OCPP 2.0.1

# Status & Health-Checks
make microocpp-status
make microocpp-health
```

## 🔌 Service-URLs

| Service | URL | Charge Point ID |
|---------|-----|-----------------|
| OCPP 1.6 Simulator | http://localhost:8001 | charger-simulator-01-v16 |
| OCPP 2.0.1 Simulator | http://localhost:8002 | charger-simulator-01 |

## 📊 Make-Befehle Übersicht

### Intel/AMD64 Befehle
- `make microocpp-start` - Beide Simulatoren starten
- `make microocpp-start-v16` - Nur OCPP 1.6 Simulator
- `make microocpp-start-v201` - Nur OCPP 2.0.1 Simulator
- `make microocpp-stop` - Alle Simulatoren stoppen
- `make microocpp-restart` - Alle Simulatoren neu starten
- `make microocpp-logs` - Live-Logs aller Simulatoren
- `make microocpp-status` - Container-Status anzeigen
- `make microocpp-health` - Health-Checks durchführen

### ARM64 Befehle
- `make microocpp-start-arm64` - Beide Simulatoren ARM64-optimiert
- `make microocpp-start-v16-arm64` - Nur OCPP 1.6 ARM64
- `make microocpp-start-v201-arm64` - Nur OCPP 2.0.1 ARM64
- `make microocpp-stop-arm64` - Alle ARM64-Simulatoren stoppen
- `make microocpp-restart-arm64` - ARM64-Simulatoren neu starten
- `make microocpp-logs-arm64` - ARM64-Simulator Logs
- `make microocpp-status-arm64` - ARM64-Container Status
- `make microocpp-health-arm64` - ARM64-Health-Checks
- `make microocpp-debug-arm64` - ARM64-Debug-Informationen

### Legacy-Unterstützung
- `make simulator-start` → `make microocpp-start`
- `make simulator-stop` → `make microocpp-stop`
- `make simulator-logs` → `make microocpp-logs`

## 🔧 Konfigurationsdateien

### ARM64-spezifische Dockerfiles
- `overrides/microocpp-simulator/Dockerfile.arm64` - ARM64-optimiertes Build für OCPP 2.0.1
- `overrides/microocpp-simulator/Dockerfile.v16.arm64` - ARM64-optimiertes Build für OCPP 1.6

### Protocol-spezifische Configs
- `overrides/microocpp-simulator/config/ocpp-1.6-config.json` - OCPP 1.6 Konfiguration
- `overrides/microocpp-simulator/config/ocpp-2.0.1-config.json` - OCPP 2.0.1 Konfiguration
- `overrides/microocpp-simulator/config/citrineos-default.json` - CitrineOS-Standardkonfiguration

### Docker-Compose Override
- `overrides/microocpp-simulator/docker-compose.arm64.yml` - ARM64-Services mit Platform-Spezifikation

## 🔗 CitrineOS-Integration

Die Simulatoren werden automatisch für CitrineOS konfiguriert:
- **WebSocket-Endpunkt**: `ws://citrineos:8081`
- **Automatische Registrierung**: Charge Points werden bei CitrineOS registriert
- **Konfigurationsskript**: `./overrides/microocpp-simulator/configure-citrineos.sh`

## 🧪 Test-Workflows

### Basis-Funktionalität testen
1. CitrineOS starten: `make start-arm64`
2. MicroOCPP starten: `make microocpp-start-arm64`
3. Simulator UI öffnen: http://localhost:8001 und http://localhost:8002
4. CitrineOS Operator UI: http://localhost:3000

### OCPP-Protokoll-Tests
1. **OCPP 1.6**: ChargePoint `charger-simulator-01-v16` auf Port 8001
2. **OCPP 2.0.1**: ChargePoint `charger-simulator-01` auf Port 8002
3. **Operationen testen**: StartTransaction, StopTransaction, Heartbeat
4. **Status verfolgen**: CitrineOS Operator UI für Live-Monitoring

## 🏥 Health-Checks & Debugging

### Standard Health-Check
```bash
make microocpp-health        # Intel/AMD64
make microocpp-health-arm64  # ARM64
```

### Erweiterte Debug-Informationen (nur ARM64)
```bash
make microocpp-debug-arm64
```
Zeigt:
- System- und Container-Architektur
- OCPP-Konfiguration beider Simulatoren
- Container-Ressourcen-Nutzung
- Prozess-Status

### Manual Health-Check
```bash
# OCPP 1.6 Simulator
curl http://localhost:8001

# OCPP 2.0.1 Simulator  
curl http://localhost:8002
```

## ⚠️ Wichtige Hinweise

### ARM64 (Apple Silicon)
- Längere Startup-Zeiten durch Architektur-Optimierung
- ARM64-Container nutzen native Performance
- Automatische Platform-Erkennung

### Intel/AMD64 
- Standard-Performance und -Kompatibilität
- Universelle Docker-Images
- Bewährte Stabilität

### Port-Konflikte vermeiden
- Port 8001: Exklusiv für OCPP 1.6 Simulator
- Port 8002: Exklusiv für OCPP 2.0.1 Simulator
- Überprüfe mit `make microocpp-status` oder `make microocpp-status-arm64`

## 🔄 Workflow-Integration

Die MicroOCPP-Simulatoren integrieren sich nahtlos in bestehende Workflows:

1. **Entwicklung**: Lokaler Test verschiedener OCPP-Versionen
2. **CI/CD**: Automatisierte OCPP-Konformitätstests
3. **Staging**: Realistisches Lade-Szenario-Testing
4. **Produktion**: Monitoring und Belastungstests

Nutze `make urls` für eine vollständige Service-Übersicht oder `make quick-start` für einen geführten Einstieg. 