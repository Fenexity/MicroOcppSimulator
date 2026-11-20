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
./generate-depot.sh depot-data/chargers-darmstadt.csv 1.6
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

### Firmware version

Every simulator reports `firmwareVersion` in its BootNotification. It comes
from the environment variable `FIRMWARE_VERSION`; the default is
`fenexity-sim-1.0.0` (`DEFAULT_FIRMWARE_VERSION` in `src/main.cpp`).

Interoperability profiles in Fenexity Charging Management match the firmware
version exactly. Change the default only when the simulator's charging
behaviour changes, and create a new profile revision from an FNX Testing run
for the new version.

### Simulation time (development only)

On a Fenexity development stack started with `./setup.sh --sim-clock`, a simulator
can follow the shared simulation time of the platform (ADR 0025 in the Hub's
architecture documentation, PLA-746). It is off unless `FNX_CLOCK=sim` is set;
without it the simulator keeps its own clock, synchronized by BootNotification
and Heartbeat as before.

| Variable | Meaning |
|---|---|
| `FNX_CLOCK` | Unset, empty or `system`: real time. `sim`: shared simulation time. Any other value refuses to start. |
| `FNX_CLOCK_REDIS_URL` | `redis://:<password>@<host>:<port>/15`, the database with the timebase. Never logged. |
| `FENEXITY_DEPLOYMENT_CLASS` | Must be `development`; `ENVIRONMENT=production` or `FENEXITY_ENVIRONMENT=prod` refuse simulation time. |
| `FNX_SIM_CLOCK_READY_FILE` | Readiness marker, default `/tmp/fnx-sim-clock-ready`; present while the timebase is valid. |

With `FNX_CLOCK=sim`:

- **Business time:** once the CSMS has set the time (BootNotification), every
  OCPP timestamp (StatusNotification, StartTransaction, MeterValues,
  StopTransaction) is the simulation time at that moment, also at rate > 1 and
  frozen while the run is paused. Smart-charging schedules, reservations and
  the plug-in timeout (`ConnectionTimeOut`) follow it too.
- **Energy:** accrues over elapsed simulation time: one simulated hour at
  11 kW reports about 11 kWh at any rate; nothing accrues while paused.
- **Real time stays real:** websocket ping, stale detection and reconnect,
  Heartbeat interval, request timeouts, boot retries and
  `MeterValueSampleInterval` keep real seconds, so the connection is not
  stressed by a high rate. Periodic MeterValues therefore cover
  `MeterValueSampleInterval` × rate of simulated time each; while paused they
  repeat the frozen timestamp and energy.
- **Retry backoff:** `TransactionMessageRetryInterval` for StartTransaction and
  StopTransaction is measured on the library clock, so it shrinks with the rate
  and waits while paused.
- **Timebase rules:** the simulator refuses to start without a valid timebase,
  keeps the last one (and removes the readiness marker) while it is missing or
  invalid, follows changes within milliseconds (subscription) and re-reads it
  every 5 s, and exits with status 75 when a new run starts, so Docker restarts
  it on the new run.

Images with this support carry the label `io.fenexity.microocpp.timebase="1"`.

The simulator patches one file of the vendored MicroOcpp library for this:
`lib/MicroOcpp/src/MicroOcpp/Core/Time.h` and `Time.cpp` (an optional time
source for `Clock::now()`, marked `Fenexity PLA-746`). Re-apply it when the
library is updated.

### Unit tests

```bash
cmake -S . -B build -DMO_SIM_BUILD_TESTS=ON -DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build build --target mo_sim_tests
ctest --test-dir build --output-on-failure
```

macOS clang treats warnings in the vendored mbedtls as errors; build the tests
in a Linux container (as CI does) instead.

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
├── Dockerfile
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
