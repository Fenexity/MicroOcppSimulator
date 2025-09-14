# Fenexity MicroOCPP Simulator

This repository is a fork of [matth-x/MicroOcppSimulator](https://github.com/matth-x/MicroOcppSimulator) with integrated modifications for the Fenexity CSMS Platform.

## Features

- **Dual OCPP Protocol Support**: OCPP 1.6 and OCPP 2.0.1 simultaneously
- **Multi-Container Architecture**: Skalierbare Container für beliebig viele Simulatoren
- **OCPP 1.6 Compliance Fix**: Integrated directly into the code
- **Environment Variable Configuration**: Dynamic configuration support
- **Automatic CitrineOS Integration**: Seamless connection with fenexity-csms network
- **ARM64 Optimized**: Specifically developed for Apple Silicon

## Quick Start

Clone this repository:

```bash
git clone git@github.com:Fenexity/MicroOcppSimulator.git
```

### Einfacher Setup (Empfohlen)

#### Standard Setup (2 Simulatoren)

```bash
# Start both simulators - One command, everything automatic!
docker-compose up -d

# Check status
docker-compose ps

# View live logs
docker-compose logs -f

# Stop
docker-compose down
```

#### Multi-Container Setup (Skalierbar)

```bash
# 1. Konfiguriere gewünschte Anzahl Simulatoren
nano simulator-config.yml

# 2. Generiere Docker Compose Konfiguration
./generate-simulators.sh

# 3. Starte alle Simulatoren
docker-compose -f docker-compose.generated.yml up -d

# 4. Status prüfen
docker-compose -f docker-compose.generated.yml ps

# 5. Bereinigen
./cleanup-simulators.sh
```

### Automatic CitrineOS Integration

The simulators configure themselves **automatically** for CitrineOS:

1. **Init-Container** dynamically determines CitrineOS IP address
2. **WebSocket Configuration** is created at runtime
3. **BasicAuth Passwords** are registered in CitrineOS database
4. **Simulators start** with correct configuration

**A single `docker-compose up -d` is sufficient!** ✅

## Service URLs

| Service | URL | Charge Point ID | OCPP Version |
|---------|-----|-----------------|--------------|
| OCPP 1.6 Simulator | http://localhost:8001 | charger-1.6 | 1.6 |
| OCPP 2.0.1 Simulator | http://localhost:8002 | charger-201 | 2.0.1 |

## Architecture

### Multi-Container-Architektur

Die neue skalierbare Multi-Container-Architektur ermöglicht es, beliebig viele OCPP-Simulatoren parallel zu betreiben:

#### Kernkomponenten

1. **`simulator-config.yml`** - Zentrale Konfigurationsdatei
   - Definiert Anzahl der Simulatoren pro OCPP-Version
   - Konfiguriert Ports, URLs und IDs
   - Einfach anpassbar für verschiedene Testszenarien

2. **`generate-simulators.sh`** - Automatischer Generator
   - Liest simulator-config.yml
   - Erstellt docker-compose.generated.yml
   - Generiert individuelle mo_store-Verzeichnisse
   - Konfiguriert jeden Simulator mit eindeutiger ID

3. **`cleanup-simulators.sh`** - Bereinigungsscript
   - Stoppt alle generierten Container
   - Entfernt generierte Dateien
   - Verschiedene Bereinigungsoptionen

#### Beispiel-Konfiguration

```yaml
# simulator-config.yml
simulators:
  v16:
    count: 5          # 5x OCPP 1.6 Simulatoren
    base_port: 8101   # Ports 8101-8105
    base_charger_id: "charger-v16"
  v201:
    count: 3          # 3x OCPP 2.0.1 Simulatoren  
    base_port: 8201   # Ports 8201-8203
    base_charger_id: "charger-v201"
```

#### Generierte Container

| Simulator | Container | Port | Charger ID | OCPP Version |
|-----------|-----------|------|------------|--------------|
| v16-001 | microocpp-sim-v16-001 | 8101 | charger-v16-001 | 1.6 |
| v16-002 | microocpp-sim-v16-002 | 8102 | charger-v16-002 | 1.6 |
| v201-001 | microocpp-sim-v201-001 | 8201 | charger-v201-001 | 2.0.1 |

### Integrated Fenexity Modifications

1. **OCPP 1.6 Compliance Fix** (directly in `lib/MicroOcpp/src/MicroOcpp/Operations/StartTransaction.cpp`):
   - ✅ Correct StartTransaction.req without transactionId
   - ✅ Accept Transaction ID from CSMS (OCPP 1.6 standard)
   - ✅ No own Transaction ID generation

2. **Environment Variable Support** (directly in `src/main.cpp`):
   - ✅ `CENTRAL_SYSTEM_URL` for WebSocket endpoint
   - ✅ `CHARGER_ID` for charger identification
   - ✅ Automatic fallback values

3. **Unified ARM64 Docker Build**:
   - ✅ One Dockerfile for both OCPP versions
   - ✅ Dynamic CMake configuration
   - ✅ Environment-based configuration

## Configuration

### Environment Variables

| Variable | OCPP 1.6 | OCPP 2.0.1 | Description |
|----------|----------|------------|-------------|
| `CENTRAL_SYSTEM_URL` | `ws://citrineos:8092/ocpp16` | `ws://citrineos:8082/ocpp201` | WebSocket endpoint |
| `CHARGER_ID` | `charger-1.6` | `charger-201` | Charger identification |
| `MO_ENABLE_V201` | `0` | `1` | Enable OCPP version |
| `BASIC_AUTH_PASSWORD` | - | `fenexity_test_2025` | Auth for OCPP 2.0.1 |

### Multi-Container Configuration

#### Konfigurationsdatei: `simulator-config.yml`

```yaml
simulators:
  v16:
    count: 3                    # Anzahl OCPP 1.6 Simulatoren
    base_port: 8101            # Startport (8101, 8102, 8103)
    ocpp_version: "1.6"        # OCPP Version
    base_charger_id: "charger-v16"  # Basis-ID
    csms_url_template: "ws://citrineos:8092/{charger_id}"
    
  v201:
    count: 2                   # Anzahl OCPP 2.0.1 Simulatoren  
    base_port: 8201           # Startport (8201, 8202)
    ocpp_version: "2.0.1"     # OCPP Version
    base_charger_id: "charger-v201"
    auth_password: "fenexity_test_2025"
```

#### Workflow

1. **Konfiguration anpassen**: `simulator-config.yml` bearbeiten
2. **Generierung**: `./generate-simulators.sh` ausführen  
3. **Start**: `docker-compose -f docker-compose.generated.yml up -d`
4. **Bereinigung**: `./cleanup-simulators.sh`

### Directory Structure

```
MicroOcppSimulator/
├── lib/MicroOcpp/                  # ✅ Modified MicroOCPP library
│   └── src/MicroOcpp/Operations/
│       └── StartTransaction.cpp    # 🔧 OCPP 1.6 Compliance Fix integrated
├── src/main.cpp                    # 🔧 Environment Variable Support integrated
├── config/                         # 📁 OCPP configuration files
├── mo_store_v16/                   # 📁 OCPP 1.6 state files (Template)
├── mo_store_v201/                  # 📁 OCPP 2.0.1 state files (Template)
├── mo_store_generated/             # 📁 Generierte Simulator-Konfigurationen
│   ├── sim_v16_001/               # 📁 Simulator 1 (OCPP 1.6)
│   ├── sim_v16_002/               # 📁 Simulator 2 (OCPP 1.6)
│   └── sim_v201_001/              # 📁 Simulator 1 (OCPP 2.0.1)
├── templates/                      # 📁 mo_store Templates
├── simulator-config.yml            # ⚙️ Multi-Container Konfiguration
├── generate-simulators.sh         # 🔧 Generator-Script
├── cleanup-simulators.sh          # 🧹 Bereinigungsscript
├── docker-compose.yml              # 🐳 Standard 2-Container Setup
├── docker-compose.generated.yml   # 🐳 Generierte Multi-Container Orchestration
└── Dockerfile.arm64                # 🐳 ARM64-optimized build
```

## Testing

### Basic Functionality Test

1. Start the simulators:
   ```bash
   docker-compose up -d
   ```

2. Check API connectivity:
   ```bash
   # Test OCPP 1.6
   curl http://localhost:8001/api/connectors
   
   # Test OCPP 2.0.1
   curl http://localhost:8002/api/connectors
   ```

3. Open web interfaces:
   - OCPP 1.6: http://localhost:8001
   - OCPP 2.0.1: http://localhost:8002

### OCPP Protocol Tests

#### Standard Setup (2 Container)
1. **OCPP 1.6**: ChargePoint `charger-1.6` on port 8001
2. **OCPP 2.0.1**: ChargePoint `charger-201` on port 8002

#### Multi-Container Setup (Skalierbar)
1. **OCPP 1.6**: ChargePoint `charger-v16-001`, `charger-v16-002`, etc.
2. **OCPP 2.0.1**: ChargePoint `charger-v201-001`, `charger-v201-002`, etc.
3. **Port-Range**: Konfigurierbar über `simulator-config.yml`

#### Test-Szenarien
- **Load Testing**: Viele Simulatoren für Lasttests
- **Feature Testing**: Verschiedene OCPP-Versionen parallel  
- **Development**: Einzelne Simulatoren für spezifische Tests

### Multi-Container Management

```bash
# Alle Container-Status anzeigen
docker-compose -f docker-compose.generated.yml ps

# Logs eines spezifischen Simulators
docker-compose -f docker-compose.generated.yml logs -f microocpp-sim-v16-001

# Einzelnen Simulator stoppen
docker-compose -f docker-compose.generated.yml stop microocpp-sim-v16-001

# Einzelnen Simulator neustarten  
docker-compose -f docker-compose.generated.yml restart microocpp-sim-v201-002

# Alle Simulatoren skalieren
# 1. simulator-config.yml anpassen
# 2. ./generate-simulators.sh --clean
# 3. docker-compose -f docker-compose.generated.yml up -d
```

## CitrineOS Integration

### Automatic Network Configuration

- **Network**: `fenexity-csms` (external)
- **OCPP 1.6 Endpoint**: `ws://citrineos:8092/ocpp16`
- **OCPP 2.0.1 Endpoint**: `ws://citrineos:8082/ocpp201`

### Charger Registration

The simulators automatically register with CitrineOS:
- **OCPP 1.6**: `charger-1.6`
- **OCPP 2.0.1**: `charger-201`

## Debugging

### Container Logs

```bash
# All logs
docker-compose logs -f

# OCPP 1.6 only
docker-compose logs -f microocpp-sim-v16

# OCPP 2.0.1 only
docker-compose logs -f microocpp-sim-v201
```

### OCPP 1.6 Compliance Debugging

```bash
# Filter StartTransaction logs
docker-compose logs microocpp-sim-v16 | grep -E "FENEXITY_OCPP16_FIX|Transaction|StartTransaction"
```

### Configuration Debugging

```bash
# Show current WebSocket configuration
cat mo_store_v16/ws-conn.jsn | grep -E '"value"|"valActual"'
cat mo_store_v201/ws-conn-v201.jsn | grep -E '"valActual"'
```

## Important Notes

### ARM64 Performance

- ⚡ **Native Performance**: Optimized for Apple Silicon
- 🔧 **Build Time**: Longer compilation time due to architecture optimization
- 📦 **Image Size**: Compact Alpine-based images

### Network Configuration

- 🌐 **External Network**: `fenexity-csms` must exist
- 🔌 **Port Mapping**: 8001 (OCPP 1.6), 8002 (OCPP 2.0.1)
- 🔐 **Security**: OCPP 2.0.1 with Basic Auth

### Port Conflict Avoidance

- Port 8001: Exclusive for OCPP 1.6 Simulator
- Port 8002: Exclusive for OCPP 2.0.1 Simulator
- Check with `docker-compose ps` for status

## Production Deployment

### Prerequisites

```bash
# Create Fenexity CSMS network
docker network create fenexity-csms

# Start CitrineOS (separate repository)
# ...
```

### Deployment

```bash
# Clone repository
git clone https://github.com/Fenexity/MicroOcppSimulator.git
cd MicroOcppSimulator

# Start simulators
docker-compose up -d

# Test functionality
curl http://localhost:8001/api/connectors
curl http://localhost:8002/api/connectors
```

## Development

### Code Modifications

The main Fenexity modifications are directly integrated into the code:

1. **StartTransaction.cpp**: OCPP 1.6 Compliance Fix
2. **main.cpp**: Environment Variable Support
3. **Dockerfile.arm64**: Unified ARM64 Build
4. **docker-compose.yml**: Dual-Simulator Setup

### Upstream Updates

```bash
# Add upstream remote
git remote add upstream https://github.com/matth-x/MicroOcppSimulator.git

# Fetch updates (careful due to modifications)
git fetch upstream
git merge upstream/main  # Manual conflict resolution required
```

---

**Fenexity CSMS Platform** - Developed for ARM64 with OCPP 1.6/2.0.1 Dual-Support 🚀