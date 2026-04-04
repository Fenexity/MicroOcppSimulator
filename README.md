# MicroOCPP Simulator

This repository extends
[matth-x/MicroOcppSimulator](https://github.com/matth-x/MicroOcppSimulator)
with project-specific Docker, depot generation, and CitrineOS integration.

## What This Repo Provides

- OCPP 1.6 and OCPP 2.0.1 simulator support
- Docker-based local simulator setup
- Depot CSV to simulator generation via `./generate-depot.sh`
- Multi-container generation via `./generate-simulators.sh`
- Automatic CitrineOS IP discovery for generated `mo_store` data

## Requirements

- Docker
- Docker Compose (`docker compose` or `docker-compose`)
- `yq` for `generate-simulators.sh`

Create the shared external network before starting containers:

```bash
docker network create fnx-platform-net
```

## Quick Start

Clone the repository:

```bash
git clone git@github.com:Fenexity/MicroOcppSimulator.git
cd MicroOcppSimulator
```

### Depot Generator

Generate depot simulators from a CSV file:

```bash
./generate-depot.sh depot-data/darmstadt-depot.csv 1.6
```

If CitrineOS restarted and its container IP changed, refresh the stored URLs:

```bash
./generate-depot.sh --update-url
```

Generate files only, without starting containers:

```bash
./generate-depot.sh depot-data/darmstadt-depot.csv 1.6 --no-start
```

Generated outputs:

- `simulator-config-depot.yml`
- `docker-compose-depot.yml`
- `mo_store_depot/`

### Multi-Container Setup

Edit the simulator definition:

```bash
nano simulator-config.yml
```

Generate and start:

```bash
./start-simulators.sh
```

Management commands:

```bash
docker-compose -f docker-compose.generated.yml ps
docker-compose -f docker-compose.generated.yml logs -f
docker-compose -f docker-compose.generated.yml down
./cleanup-simulators.sh
```

### Standalone Setup

For the fixed two-simulator setup:

```bash
docker-compose up -d
docker-compose down
```

## Configuration

The shared external network is configured in:

- `docker-compose.yml`
- `docker-compose.generated.yml`
- `docker-compose-depot.yml`
- `simulator-config.yml`
- `simulator-config-depot.yml`

The current external network name is:

```text
fnx-platform-net
```

### `simulator-config.yml`

Example:

```yaml
global:
  network_name: "fnx-platform-net"
  citrineos_service: "fenexity-citrineos"
  mo_store_base_path: "./mo_store_generated"

simulators:
  v16:
    count: 2
    base_port: 7101
    ocpp_version: "1.6"
    csms_url_template: "ws://citrineos:8092/{charger_id}"
    base_charger_id: "charger-v16"
    container_prefix: "microocpp-sim-v16"
    environment:
      MO_ENABLE_V201: "0"

  v201:
    count: 1
    base_port: 7201
    ocpp_version: "2.0.1"
    csms_url_template: "ws://citrineos:8081/{charger_id}"
    base_charger_id: "charger-v201"
    container_prefix: "microocpp-sim-v201"
    auth_password: ""
    environment:
      MO_ENABLE_V201: "1"
      BASIC_AUTH_PASSWORD: ""
```

## CitrineOS Integration

The simulator workflow expects:

- a running CitrineOS container
- the simulator containers attached to `fnx-platform-net`
- the CitrineOS container discoverable by name for IP detection

The scripts update generated WebSocket configuration with the detected
CitrineOS container IP. If the IP changes after a restart, run:

```bash
./generate-depot.sh --update-url
```

## Repository Layout

```text
.
├── AGENTS.md
├── Dockerfile.arm64
├── README.md
├── cleanup-simulators.sh
├── config/
├── depot-data/
├── docker-compose-depot.yml
├── docker-compose.generated.yml
├── docker-compose.standalone.yml
├── docker-compose.yml
├── generate-depot.sh
├── generate-simulators.sh
├── mo_store/
├── scripts/
├── simulator-config-depot.yml
├── simulator-config.yml
├── start-simulators.sh
└── templates/
```

## Notes

- `docker-compose.generated.yml` and `docker-compose-depot.yml` are generated
  artifacts and may be overwritten by the scripts.
- Depot generation uses `charging_station_id` from the input CSV.
- OCPP 1.6 and OCPP 2.0.1 use different backend ports and `mo_store`
  templates.
