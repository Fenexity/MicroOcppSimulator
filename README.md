# Fenexity MicroOCPP Simulator

This repository is a fork of [matth-x/MicroOcppSimulator](https://github.com/matth-x/MicroOcppSimulator) with integrated modifications for the Fenexity CSMS Platform.

## Features

- **Dual OCPP Protocol Support**: OCPP 1.6 and OCPP 2.0.1 simultaneously
- **OCPP 1.6 Compliance Fix**: Integrated directly into the code
- **Environment Variable Configuration**: Dynamic configuration support
- **Automatic CitrineOS Integration**: Seamless connection with fenexity-csms network
- **ARM64 Optimized**: Specifically developed for Apple Silicon

## Quick Start

Clone this repository with its submodules:

```bash
git clone --recurse-submodules git@github.com:Fenexity/MicroOcppSimulator.git
```

### Simple Setup (Recommended)

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

### Directory Structure

```
MicroOcppSimulator/
├── lib/MicroOcpp/                  # ✅ Modified MicroOCPP library
│   └── src/MicroOcpp/Operations/
│       └── StartTransaction.cpp    # 🔧 OCPP 1.6 Compliance Fix integrated
├── src/main.cpp                    # 🔧 Environment Variable Support integrated
├── config/                         # 📁 OCPP configuration files
├── mo_store_v16/                   # 📁 OCPP 1.6 state files
├── mo_store_v201/                  # 📁 OCPP 2.0.1 state files
├── docker-compose.yml              # 🐳 Unified container orchestration
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

1. **OCPP 1.6**: ChargePoint `charger-1.6` on port 8001
2. **OCPP 2.0.1**: ChargePoint `charger-201` on port 8002
3. **Operations**: Test StartTransaction, StopTransaction, Heartbeat
4. **Status monitoring**: Use CitrineOS Operator UI for live monitoring

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
git clone --recurse-submodules https://github.com/Fenexity/MicroOcppSimulator.git
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