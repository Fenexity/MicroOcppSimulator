# MicroOCPP Multi-Container Architecture - Quick Start Guide

## 🎯 Überblick

Die neue Multi-Container-Architektur ermöglicht es, **beliebig viele OCPP-Simulatoren** parallel zu betreiben. Jeder Simulator läuft in seinem eigenen Container mit individueller Konfiguration.

## 🚀 Quick Start

### 1. Abhängigkeiten installieren

```bash
# macOS
brew install yq

# Ubuntu/Debian
sudo apt-get install yq

# Alternative: Docker-basierte Installation
# (falls yq nicht direkt installiert werden kann)
```

### 2. Konfiguration anpassen

```bash
# Bearbeite die Anzahl und Konfiguration der Simulatoren
nano simulator-config.yml
```

**Beispiel-Konfiguration:**
```yaml
simulators:
  v16:
    count: 3          # 3x OCPP 1.6 Simulatoren
    base_port: 8101   # Ports: 8101, 8102, 8103
    base_charger_id: "charger-v16"
    
  v201:
    count: 2          # 2x OCPP 2.0.1 Simulatoren
    base_port: 8201   # Ports: 8201, 8202  
    base_charger_id: "charger-v201"
    auth_password: "fenexity_test_2025"
```

### 3. Container generieren und starten

```bash
# Generiere Docker Compose Konfiguration
./generate-simulators.sh

# Starte alle Simulatoren
docker-compose -f docker-compose.generated.yml up -d

# Status prüfen
docker-compose -f docker-compose.generated.yml ps
```

### 4. Zugriff auf Simulatoren

| Simulator | URL | Charger ID | OCPP Version |
|-----------|-----|------------|--------------|
| v16-001 | http://localhost:8101 | charger-v16-001 | 1.6 |
| v16-002 | http://localhost:8102 | charger-v16-002 | 1.6 |
| v16-003 | http://localhost:8103 | charger-v16-003 | 1.6 |
| v201-001 | http://localhost:8201 | charger-v201-001 | 2.0.1 |
| v201-002 | http://localhost:8202 | charger-v201-002 | 2.0.1 |

### 5. Bereinigung

```bash
# Alle Container stoppen und Dateien löschen
./cleanup-simulators.sh

# Nur Container stoppen (Konfiguration behalten)
./cleanup-simulators.sh --containers-only
```

## 📋 Test-Szenarien

```bash
# Development (2x v16 + 1x v201)
./test-multi-container.sh small

# Testing (5x v16 + 3x v201)
./test-multi-container.sh medium

# Load Testing (10x v16 + 5x v201)  
./test-multi-container.sh large

# Custom (verwende bestehende simulator-config.yml)
./test-multi-container.sh custom
```

## 🔧 Erweiterte Verwendung

### Individuelle Container-Verwaltung

```bash
# Logs eines spezifischen Simulators
docker-compose -f docker-compose.generated.yml logs -f microocpp-sim-v16-001

# Einzelnen Container stoppen
docker-compose -f docker-compose.generated.yml stop microocpp-sim-v201-001

# Einzelnen Container neustarten
docker-compose -f docker-compose.generated.yml restart microocpp-sim-v16-002
```

### Konfiguration ändern

```bash
# 1. simulator-config.yml bearbeiten
nano simulator-config.yml

# 2. Neu generieren (bereinigt automatisch)
./generate-simulators.sh --clean

# 3. Container neu starten
docker-compose -f docker-compose.generated.yml up -d
```

### Debugging

```bash
# Alle Container-Status
docker-compose -f docker-compose.generated.yml ps

# Alle Logs
docker-compose -f docker-compose.generated.yml logs -f

# Spezifische Container-Logs
docker-compose -f docker-compose.generated.yml logs -f microocpp-sim-v16-001

# Netzwerk-Status
docker network inspect fenexity-csms
```

## 📁 Generierte Dateien

Nach der Ausführung von `./generate-simulators.sh`:

```
MicroOcppSimulator/
├── docker-compose.generated.yml    # Generierte Docker Compose Datei
├── mo_store_generated/             # Individuelle Simulator-Konfigurationen
│   ├── sim_v16_001/               # OCPP 1.6 Simulator 1
│   ├── sim_v16_002/               # OCPP 1.6 Simulator 2
│   ├── sim_v16_003/               # OCPP 1.6 Simulator 3
│   ├── sim_v201_001/              # OCPP 2.0.1 Simulator 1
│   └── sim_v201_002/              # OCPP 2.0.1 Simulator 2
└── templates/                      # Template-Cache
    ├── mo_store_v16_template/
    └── mo_store_v201_template/
```

## ⚙️ Konfigurationsoptionen

### Global Settings

```yaml
global:
  network_name: "fenexity-csms"           # Docker-Netzwerk
  citrineos_service: "fenexity-citrineos" # CitrineOS Container-Name
  mo_store_base_path: "./mo_store_generated" # Basis-Pfad für mo_store
```

### Simulator Settings

```yaml
simulators:
  v16:
    count: 3                              # Anzahl Container
    base_port: 8101                       # Startport
    ocpp_version: "1.6"                   # OCPP Version
    base_charger_id: "charger-v16"        # Basis Charger-ID
    container_prefix: "microocpp-sim-v16" # Container-Name Prefix
    csms_url_template: "ws://citrineos:8092/{charger_id}" # CSMS URL
    environment:                          # Zusätzliche Umgebungsvariablen
      MO_ENABLE_V201: "0"
```

## 🐛 Troubleshooting

### Problem: yq nicht gefunden
```bash
# macOS
brew install yq

# Ubuntu
sudo apt-get update && sudo apt-get install yq
```

### Problem: Docker-Netzwerk existiert nicht
```bash
# Erstelle Fenexity CSMS Netzwerk
docker network create fenexity-csms
```

### Problem: Port-Konflikte
```bash
# Prüfe verwendete Ports
netstat -tlnp | grep :81

# Passe base_port in simulator-config.yml an
```

### Problem: Container starten nicht
```bash
# Prüfe Container-Logs
docker-compose -f docker-compose.generated.yml logs

# Prüfe Health-Checks
docker-compose -f docker-compose.generated.yml ps
```

## 📊 Performance-Tipps

### Ressourcen-Management

- **Kleine Tests**: 2-5 Simulatoren
- **Mittlere Tests**: 5-10 Simulatoren  
- **Load Tests**: 10+ Simulatoren
- **Überwachung**: `docker stats` für Ressourcen-Monitoring

### Optimierungen

```bash
# Parallele Container-Starts begrenzen
docker-compose -f docker-compose.generated.yml up -d --scale microocpp-sim-v16-001=1

# Health-Check Intervalle anpassen (in simulator-config.yml)
healthcheck:
  interval: "60s"  # Weniger häufige Checks für viele Container
```

## 🔄 Migration vom Standard-Setup

### Von docker-compose.yml zu Multi-Container

1. **Backup erstellen:**
   ```bash
   cp docker-compose.yml docker-compose.yml.backup
   ```

2. **Konfiguration migrieren:**
   ```bash
   # Aktuelle Konfiguration als Basis verwenden
   ./test-multi-container.sh custom
   ```

3. **Testen:**
   ```bash
   # Erst mit wenigen Containern testen
   ./test-multi-container.sh small
   ```

4. **Produktiv einsetzen:**
   ```bash
   # Standard-Container stoppen
   docker-compose down
   
   # Multi-Container starten
   docker-compose -f docker-compose.generated.yml up -d
   ```

---

**🎉 Fertig!** Du hast jetzt eine vollständig skalierbare OCPP-Simulator-Architektur!
